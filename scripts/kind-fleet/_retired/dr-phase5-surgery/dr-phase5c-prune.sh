#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml
PASS=$(cd /opt/am-infra-automation/terraform/kind-fleet/dr/platform && terraform output -raw argocd_admin_password)
for app in am-ai-gateway-dr am-modern-ui-dr; do
  echo "=== prune sync $app ==="
  kubectl -n argocd exec deploy/argocd-server -- sh -c \
    "argocd login localhost:8080 --username admin --password '$PASS' --plaintext --grpc-web >/dev/null && argocd app sync '$app' --server localhost:8080 --plaintext --grpc-web --prune --timeout 120" \
    2>&1 | tail -12 || true
done
sleep 40
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
kubectl get pods -n am-apps-dr
kubectl get pods -n am-agents-dr
# delete orphan empty SPCs if still present
kubectl delete secretproviderclass -n am-apps-dr am-modern-ui-dr-vault-secrets --ignore-not-found
kubectl delete secretproviderclass -n am-agents-dr am-ai-gateway-vault-secrets --ignore-not-found
sleep 10
kubectl get pods -n am-apps-dr
kubectl get pods -n am-agents-dr
