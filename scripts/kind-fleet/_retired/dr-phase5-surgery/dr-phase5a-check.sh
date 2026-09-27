#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml

echo "=== cluster secrets ==="
kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=cluster -o wide

echo "=== wait for AppSet children ==="
sleep 15
kubectl -n argocd get applicationsets
kubectl -n argocd get applications -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,DEST:.spec.destination.name --no-headers 2>/dev/null | grep -E 'dr|NAME' | head -50
echo "count=$(kubectl -n argocd get applications --no-headers 2>/dev/null | grep -c dr || true)"

# Check cluster connection via argocd-server logs / cluster list API
echo "=== cluster connection via argocd API ==="
PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)
if [[ -z "$PASS" ]]; then
  PASS=$(cd /opt/am-infra-automation/terraform/kind-fleet/dr/platform && terraform output -raw argocd_admin_password 2>/dev/null || true)
fi
# port-forward free: hit in-cluster
TOKEN=$(kubectl -n argocd exec deploy/argocd-server -- argocd login localhost:8080 --username admin --password "$PASS" --plaintext --grpc-web 2>/dev/null | true || true)
kubectl -n argocd exec deploy/argocd-server -- argocd cluster list --server localhost:8080 --plaintext --grpc-web --auth-token "$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d | true)" 2>&1 | head -20 || true

# simpler: check application controller can see cluster - look at app conditions
sleep 5
APP=$(kubectl -n argocd get applications -o name 2>/dev/null | grep 'am-gateway-dr\|am-identity-dr\|gateway' | head -1 || true)
echo "sample_app=$APP"
if [[ -n "$APP" ]]; then
  kubectl -n argocd get "$APP" -o jsonpath='{.status.conditions[*].message}{"\n"}{.status.sync.status}{"\n"}{.spec.destination}{"\n"}' 2>&1 | head -20
fi

# Cluster info annotation often shows connection
kubectl -n argocd get secret cluster-am-dr-apps -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/connection-state\.status}{"\n"}{.metadata.annotations.argocd\.argoproj\.io/connection-state\.message}{"\n"}' 2>&1 || true
