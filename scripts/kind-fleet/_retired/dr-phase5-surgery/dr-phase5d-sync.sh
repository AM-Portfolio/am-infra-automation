#!/usr/bin/env bash
# Sync Phase 5d identity wave via in-cluster argocd CLI (MCP write disabled).
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml
PASS=$(cd /opt/am-infra-automation/terraform/kind-fleet/dr/platform && terraform output -raw argocd_admin_password)

sync_one() {
  local app=$1
  echo "=== sync $app ==="
  kubectl -n argocd exec deploy/argocd-server -- sh -c \
    "argocd login localhost:8080 --username admin --password '$PASS' --plaintext --grpc-web >/dev/null && \
     argocd app sync '$app' --server localhost:8080 --plaintext --grpc-web --prune=false --timeout 300" \
    2>&1 | tail -40
}

for app in am-identity-dr am-subscription-dr am-notification-dr; do
  sync_one "$app" || echo "SYNC_FAIL $app"
done

echo "=== status ==="
kubectl -n argocd get applications am-identity-dr am-subscription-dr am-notification-dr \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status --no-headers \
  2>&1 || true

export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
kubectl get pods -n am-apps-dr -l 'app.kubernetes.io/name in (am-identity,am-subscription,am-notification)' -o wide 2>&1 || \
  kubectl get pods -n am-apps-dr | grep -iE 'identity|subscription|notification' || true
