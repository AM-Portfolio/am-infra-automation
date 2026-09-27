#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml

PASS=$(cd /opt/am-infra-automation/terraform/kind-fleet/dr/platform && terraform output -raw argocd_admin_password)
echo "got argo password len=${#PASS}"

# wait for connection state annotation
for i in 1 2 3 4 5 6; do
  ST=$(kubectl -n argocd get secret cluster-am-dr-apps -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/connection-state\.status}' 2>/dev/null || true)
  MSG=$(kubectl -n argocd get secret cluster-am-dr-apps -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/connection-state\.message}' 2>/dev/null || true)
  echo "try $i status=$ST msg=$MSG"
  [[ "$ST" == "Successful" ]] && break
  sleep 10
done

kubectl -n argocd exec deploy/argocd-server -- sh -c "argocd login localhost:8080 --username admin --password '$PASS' --plaintext --grpc-web >/dev/null && argocd cluster list --server localhost:8080 --plaintext --grpc-web" 2>&1 | head -20

echo "=== sample app ==="
kubectl -n argocd get application am-gateway-dr -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}{.status.conditions[*].message}{"\n"}' 2>&1 | head -10

export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
kubectl get ns am-apps-dr
kubectl get --raw=/version | head -c 100; echo
