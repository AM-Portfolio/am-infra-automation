#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-infra.yaml
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-prod-infra-control-plane)
VNP=$(kubectl -n vault get svc vault -o jsonpath='{.spec.ports[?(@.port==8200)].nodePort}')
# shellcheck disable=SC1091
source /data/am-state/credentials/prod/vault-root.env
ADDR="http://${IP}:${VNP}"
echo "ADDR=$ADDR"
echo "=== config ==="
curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "$ADDR/v1/auth/oidc/config" | python3 -m json.tool
echo "=== roles ==="
for r in am-admin am-ops am-viewer; do
  echo "ROLE=$r"
  curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "$ADDR/v1/auth/oidc/role/$r" | python3 -c '
import json,sys
d=json.load(sys.stdin).get("data",{})
keys=("role_type","bound_audiences","user_claim","groups_claim","allowed_redirect_uris","token_policies","oidc_scopes","bound_claims","bound_claims_type","verbose_oidc_logging")
print({k:d.get(k) for k in keys})
'
done
echo "=== auth list ==="
curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "$ADDR/v1/sys/auth" | python3 -c 'import json,sys; d=json.load(sys.stdin); print({k:v.get("type") for k,v in d.items() if k.endswith("/")})'
