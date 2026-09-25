#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
echo "=== middlewares ==="
kubectl get middleware -A --no-headers 2>/dev/null || kubectl api-resources | grep -i middleware
kubectl get middleware.traefik.io -A --no-headers 2>/dev/null | head -40
echo "=== support ingress mw ==="
kubectl -n am-agents-prod get ingress am-support-agent -o jsonpath='{.metadata.annotations}' ; echo
echo "=== qa/fin apps ==="
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-platform.yaml
kubectl -n argocd get app am-qa-agents-prod am-fin-agent-prod am-tool-agent-prod -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' --no-headers
