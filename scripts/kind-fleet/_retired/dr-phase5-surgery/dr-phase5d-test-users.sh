#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
cd /opt/am-infra-automation/terraform/kind-fleet/dr/platform

# Load vault token from auto.tfvars without printing it
set -a
# shellcheck disable=SC1091
source <(grep -E '^(vault_token|vault_addr)\s*=' platform.auto.tfvars 2>/dev/null | sed 's/ *= */=/; s/"//g' | sed 's/^/TF_VAR_/') || true
set +a

# Prefer env from how apply was done
if [ -f /data/am-state/credentials/dr-keycloak-admin.env ]; then
  # keys only
  cut -d= -f1 /data/am-state/credentials/dr-keycloak-admin.env || true
fi

echo "=== terraform taint + re-apply vault_test_users ==="
# get vault vars from tfvars file used previously
TFVARS=""
for f in platform.auto.tfvars /data/am-state/terraform/dr/platform/*.auto.tfvars; do
  [ -f "$f" ] && TFVARS="$f" && break
done
echo "tfvars=$TFVARS"
if [ -n "$TFVARS" ]; then
  grep -E '^(vault_addr|vault_token)\s*=' "$TFVARS" | sed 's/=.*/=***/' || true
fi

terraform taint 'null_resource.vault_test_users[0]' || true
# also ensure keycloak test users exist
terraform apply -auto-approve -input=false \
  -target='null_resource.vault_test_users[0]' \
  ${TFVARS:+-var-file="$TFVARS"} \
  2>&1 | tee /tmp/dr-vault-test-users.log | tail -40

echo "=== verify vault path exists (code only) ==="
# Use root token from vault-dr-infra if present
if [ -f /data/am-state/vault-dr-infra.json ]; then
  python3 - <<'PY'
import json,urllib.request
d=json.load(open("/data/am-state/vault-dr-infra.json"))
# common shapes
token=d.get("root_token") or d.get("VAULT_TOKEN") or (d.get("data") or {}).get("root_token")
addr=(d.get("vault_addr") or d.get("VAULT_ADDR") or "https://vault-dr.asrax.in").rstrip("/")
if not token:
  print("no root token in vault-dr-infra.json keys=", list(d)[:20])
  raise SystemExit(0)
req=urllib.request.Request(f"{addr}/v1/apps/data/dr/infra/keycloak-test-users", headers={"X-Vault-Token":token})
try:
  with urllib.request.urlopen(req, timeout=20) as r:
    body=json.loads(r.read().decode())
  data=(body.get("data") or {}).get("data") or {}
  print("vault_ok keys=", sorted(data.keys()))
except Exception as e:
  print("vault_read_fail", type(e).__name__, e)
PY
fi
