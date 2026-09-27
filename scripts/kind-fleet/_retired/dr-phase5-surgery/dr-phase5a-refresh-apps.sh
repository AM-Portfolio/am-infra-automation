#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml

# Recreate children so they bind to Successful cluster (docker IP)
kubectl -n argocd get applications -o name | grep -- '-dr$' | xargs -r kubectl -n argocd delete --wait=false
# bump AppSets
kubectl -n argocd annotate applicationset am-apps-dr-fleet argocd.argoproj.io/refresh="$(date +%s)" --overwrite 2>/dev/null || true
kubectl -n argocd annotate applicationset am-agents-dr-fleet argocd.argoproj.io/refresh="$(date +%s)" --overwrite 2>/dev/null || true
# force applicationset reconcile by touching
kubectl -n argocd patch applicationset am-apps-dr-fleet --type merge -p '{"metadata":{"annotations":{"am.asrax.in/reconcile":"'$(date +%s)'"}}}' 2>/dev/null || true
kubectl -n argocd patch applicationset am-agents-dr-fleet --type merge -p '{"metadata":{"annotations":{"am.asrax.in/reconcile":"'$(date +%s)'"}}}' 2>/dev/null || true

sleep 25
echo "=== apps ==="
kubectl -n argocd get applications -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,DEST:.spec.destination.name --no-headers | grep -- '-dr' | head -40
echo "count=$(kubectl -n argocd get applications --no-headers | grep -c -- '-dr' || true)"

echo "=== gateway conditions ==="
kubectl -n argocd get application am-gateway-dr -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}{.status.conditions[*].type}{"="}{.status.conditions[*].message}{"\n"}' 2>&1 | head -5

PASS=$(cd /opt/am-infra-automation/terraform/kind-fleet/dr/platform && terraform output -raw argocd_admin_password)
kubectl -n argocd exec deploy/argocd-server -- sh -c "argocd login localhost:8080 --username admin --password '$PASS' --plaintext --grpc-web >/dev/null && argocd cluster list --server localhost:8080 --plaintext --grpc-web" 2>&1 | head -10

echo PHASE5A_CLUSTER_OK
