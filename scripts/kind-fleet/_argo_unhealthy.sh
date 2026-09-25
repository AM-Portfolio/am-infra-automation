#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-platform.yaml
kubectl -n argocd get app -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' --no-headers | grep -v 'Synced.*Healthy' || true
echo ---
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
kubectl -n am-agents-prod get middleware 2>/dev/null || kubectl get middleware -A 2>/dev/null | head -40
echo ---
# modern-ui ingress priority for /
kubectl -n am-apps-prod get ingress -o custom-columns='NAME:.metadata.name,HOSTS:.spec.rules[*].host,PATHS:.spec.rules[*].http.paths[*].path' --no-headers | head -40
