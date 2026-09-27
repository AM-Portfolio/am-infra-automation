#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml
PASS=$(cd /opt/am-infra-automation/terraform/kind-fleet/dr/platform && terraform output -raw argocd_admin_password)

for app in am-gateway-dr am-ai-gateway-dr am-modern-ui-dr am-asrax-proxy-dr am-api-gateway-dr; do
  echo "=== hard refresh+sync $app ==="
  kubectl -n argocd annotate application "$app" argocd.argoproj.io/refresh=hard --overwrite
  kubectl -n argocd exec deploy/argocd-server -- sh -c \
    "argocd login localhost:8080 --username admin --password '$PASS' --plaintext --grpc-web >/dev/null && \
     argocd app sync '$app' --server localhost:8080 --plaintext --grpc-web --prune=false --timeout 180" \
    2>&1 | tail -15 || echo "sync_fail $app"
done

sleep 20
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
echo "=== SPC objects sample ==="
kubectl get secretproviderclass -n am-apps-dr am-gateway-dr-vault-secrets -o jsonpath='{.spec.parameters.objects}' | head -c 400; echo
echo "=== pods ==="
kubectl get pods -n am-apps-dr
kubectl get pods -n am-agents-dr
