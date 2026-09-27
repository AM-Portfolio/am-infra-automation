#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
cd /opt/am-infra-automation/terraform/kind-fleet/dr/platform

echo "=== vault_addr from tfvars (value ok to show) ==="
grep -E '^vault_addr' platform.auto.tfvars || true

echo "=== vault-dr-infra.json keys ==="
python3 - <<'PY'
import json
d=json.load(open("/data/am-state/vault-dr-infra.json"))
print(type(d), list(d)[:30] if isinstance(d,dict) else d)
PY

echo "=== get test passwords from terraform state (lengths only) ==="
terraform state show 'module.keycloak.random_password.test_user[0]' 2>&1 | head -20 || true
# output sensitive
terraform output -json 2>/dev/null | python3 - <<'PY' || true
import json,sys
raw=sys.stdin.read()
if not raw.strip():
  print("no outputs"); raise SystemExit
d=json.loads(raw)
for k,v in d.items():
  if "test" in k.lower() or "user" in k.lower() or "keycloak" in k.lower():
    print(k, "sensitive=", v.get("sensitive"), "type=", v.get("type"))
PY
