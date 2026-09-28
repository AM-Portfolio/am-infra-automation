#!/usr/bin/env bash
set -euo pipefail
BASE=/home/am-ops/src/am-infra-automation
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-infra.yaml

cd "$BASE/terraform/kind-fleet/prod/stores"
# ensure tfvars present
if [[ ! -f oidc_client_secrets.auto.tfvars ]]; then
  echo "missing oidc_client_secrets.auto.tfvars"
  exit 1
fi

echo "=== stores: plan vault+minio OIDC ==="
terraform plan -input=false -target=module.vault -target=module.minio \
  -out=/tmp/stores-oidc.plan 2>&1 | tee /tmp/tf-stores-plan-final.log | \
  grep -E 'Plan:|oidc|OPENID|vault_jwt|will be|Error|Warning: Value' | head -60

echo "=== stores: apply ==="
terraform apply -input=false /tmp/stores-oidc.plan 2>&1 | tee /tmp/tf-stores-apply-final.log | \
  grep -E 'Apply complete|Error|Modifying|Creating|Destruction' | head -40

echo "=== verify minio env ==="
kubectl -n infra get sts minio -o yaml | grep -E 'MINIO_IDENTITY_OPENID|MINIO_BROWSER' | sed 's/CLIENT_SECRET:.*/CLIENT_SECRET: ***/'

echo "=== verify vault oidc ==="
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-prod-infra-control-plane)
VNP=$(kubectl -n vault get svc vault -o jsonpath='{.spec.ports[?(@.port==8200)].nodePort}')
# shellcheck disable=SC1091
source /data/am-state/credentials/prod/vault-root.env
curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "http://${IP}:${VNP}/v1/auth/oidc/config" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin).get("data",{}); print("default_role",d.get("default_role"),"client",d.get("oidc_client_id"))'

echo "STORES_DONE"
