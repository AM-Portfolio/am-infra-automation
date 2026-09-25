#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
echo "=== agents not ready ==="
kubectl -n am-agents-prod get pods --no-headers | awk '$3!="Running" || $2!~/^[0-9]+\/[0-9]+$/ {print} {split($2,a,"/"); if(a[1]!=a[2]) print}'
kubectl -n am-agents-prod get pods --no-headers
echo "=== qa logs ==="
POD=$(kubectl -n am-agents-prod get pods -l app.kubernetes.io/instance=am-qa-agents-prod -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$POD" ]; then
  kubectl -n am-agents-prod get pod "$POD"
  kubectl -n am-agents-prod logs "$POD" --tail=40 2>&1 | grep -vE 'password|secret|token|Bearer' || true
fi
echo "=== support worker ==="
kubectl -n am-agents-prod get deploy am-support-agent-worker -o wide
