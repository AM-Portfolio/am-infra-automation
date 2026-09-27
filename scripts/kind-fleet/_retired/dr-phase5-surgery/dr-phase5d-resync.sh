#!/usr/bin/env bash
# Refresh + sync Phase 5d after gitops merge.
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml
PASS=$(cd /opt/am-infra-automation/terraform/kind-fleet/dr/platform && terraform output -raw argocd_admin_password)

login() {
  kubectl -n argocd exec deploy/argocd-server -- sh -c \
    "argocd login localhost:8080 --username admin --password '$PASS' --plaintext --grpc-web >/dev/null"
}

echo "=== refresh apps ==="
login
for app in am-identity-dr am-subscription-dr am-notification-dr am-modern-ui-dr; do
  kubectl -n argocd exec deploy/argocd-server -- sh -c \
    "argocd app get '$app' --refresh --server localhost:8080 --plaintext --grpc-web >/dev/null" || true
done
sleep 5

sync_one() {
  local app=$1
  echo "=== sync $app ==="
  kubectl -n argocd exec deploy/argocd-server -- sh -c \
    "argocd login localhost:8080 --username admin --password '$PASS' --plaintext --grpc-web >/dev/null && \
     argocd app sync '$app' --server localhost:8080 --plaintext --grpc-web --prune --timeout 300" \
    2>&1 | tail -25 || echo "SYNC_FAIL $app"
}

for app in am-identity-dr am-subscription-dr am-notification-dr am-modern-ui-dr; do
  sync_one "$app"
done

echo "=== argo status ==="
kubectl -n argocd get applications am-identity-dr am-subscription-dr am-notification-dr am-modern-ui-dr \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status --no-headers

echo "=== wait pods ==="
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
# bounce pods so CSI remounts new SPC
for d in am-identity-dr am-subscription-dr am-notification-dr am-modern-ui-dr; do
  kubectl -n am-apps-dr rollout restart "deploy/$d" 2>/dev/null || true
done
sleep 15
kubectl get pods -n am-apps-dr | grep -iE 'NAME|identity|subscription|notification|modern|gateway' || kubectl get pods -n am-apps-dr

echo "=== ingress hosts ==="
kubectl get ingress -n am-apps-dr -o custom-columns=NAME:.metadata.name,HOSTS:.spec.rules[*].host,PATHS:.spec.rules[*].http.paths[*].path
