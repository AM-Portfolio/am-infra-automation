#!/usr/bin/env bash
set -euo pipefail
cd /home/am-ops/src/am-infra-automation/terraform/kind-fleet/prod/stores

echo "=== import existing oidc auth ==="
terraform import -input=false 'module.vault.vault_jwt_auth_backend.oidc[0]' oidc 2>&1 | tee /tmp/tf-vault-import.log | tail -20

echo "=== plan vault oidc ==="
terraform plan -input=false -target=module.vault -out=/tmp/stores-vault-oidc.plan 2>&1 | tee /tmp/tf-vault-plan.log | \
  grep -E 'Plan:|will be|Error|vault_jwt|vault_policy|default_role' | head -50

echo "=== apply vault oidc ==="
terraform apply -input=false /tmp/stores-vault-oidc.plan 2>&1 | tee /tmp/tf-vault-apply.log | \
  grep -E 'Apply complete|Error|Creating|Modifying|Destruction' | head -40

# shellcheck disable=SC1091
source /data/am-state/credentials/prod/vault-root.env
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-infra.yaml
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-prod-infra-control-plane)
VNP=$(kubectl -n vault get svc vault -o jsonpath='{.spec.ports[?(@.port==8200)].nodePort}')
curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "http://${IP}:${VNP}/v1/auth/oidc/config" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin).get("data",{}); print("default_role",d.get("default_role"))'
curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "http://${IP}:${VNP}/v1/auth/oidc/role?list=true" \
  | python3 -c 'import json,sys; print("roles", json.load(sys.stdin).get("data",{}).get("keys"))'
echo VAULT_DONE
