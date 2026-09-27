#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
VAULT_TOKEN=$(python3 -c 'import json; print(json.load(open("/data/am-state/vault-dr-infra.json"))["root_token"])')
vk() {
  KUBECONFIG=/data/am-state/kubeconfig.am-dr-infra.yaml kubectl -n vault exec vault-0 -- \
    env VAULT_TOKEN="$VAULT_TOKEN" VAULT_ADDR=http://127.0.0.1:8200 vault "$@"
}
echo "=== infra ==="
vk kv list apps/dr/infra/
echo "=== services (count) ==="
vk kv list -format=json apps/dr/services/ | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]["keys"]))'
echo "=== identity OIDC ==="
vk kv get -format=json -mount=apps dr/infra/identity | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["data"]; print({k:d.get(k) for k in ("OIDC_ISSUER","KEYCLOAK_ADMIN_USER","KEYCLOAK_REALM") if k in d or True})'
cd /opt/am-infra-automation
PYTHONPATH=scripts/kind-fleet python3 -m phase_gates --env dr --wave 4a 2>&1 | tee /tmp/dr-phase4-gate.log | tail -40
echo DONE
