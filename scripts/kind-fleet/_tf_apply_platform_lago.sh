#!/usr/bin/env bash
set -euo pipefail
BASE=/home/am-ops/src/am-infra-automation
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-infra.yaml

# Ensure oauth2-proxy module present
test -f "$BASE/terraform/modules/apps/oauth2-proxy/main.tf"

cd "$BASE/terraform/kind-fleet/prod/platform"
terraform init -input=false >/tmp/tf-platform-init.log 2>&1 || {
  tail -40 /tmp/tf-platform-init.log
  exit 1
}

echo "=== platform plan lago+oauth2 ==="
terraform plan -input=false \
  -target=module.lago \
  -target=module.oauth2_lago \
  -out=/tmp/platform-lago-oidc.plan 2>&1 | tee /tmp/tf-platform-plan.log | \
  grep -E 'Plan:|will be|Error|oauth2|oidc_proxy|IngressRoute' | head -60

echo "=== platform apply ==="
terraform apply -input=false /tmp/platform-lago-oidc.plan 2>&1 | tee /tmp/tf-platform-apply.log | \
  grep -E 'Apply complete|Error|Creating|Modifying|Destruction' | head -50

echo "=== lago probes ==="
kubectl -n billing get deploy,svc | grep -iE 'oauth2|lago-front' || true
kubectl -n billing get ingressroute.traefik.io lago -o jsonpath='{.spec.routes[0].services}' ; echo
curl -sI --max-time 15 https://lago.asrax.in/ | head -8
echo LAGO_DONE
