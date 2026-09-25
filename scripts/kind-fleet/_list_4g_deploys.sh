#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
echo "=== apps deploys ==="
kubectl -n am-apps-prod get deploy -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas' --no-headers
echo "=== agents deploys ==="
kubectl -n am-agents-prod get deploy -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas' --no-headers
echo "=== support resources ==="
kubectl -n am-agents-prod get all -l 'app.kubernetes.io/instance=am-support-agent-prod' --no-headers 2>/dev/null || true
kubectl -n am-agents-prod get deploy -l 'app.kubernetes.io/instance=am-support-agent-prod' -o name 2>/dev/null || true
