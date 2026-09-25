#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
echo "=== PROD NS ==="
kubectl get ns | grep -E 'agent|apps' || true
echo "=== PROD deploys am-agents-prod ==="
kubectl -n am-agents-prod get deploy -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas,DESIRED:.status.replicas,IMAGE:.spec.template.spec.containers[0].image' --no-headers
echo "=== PROD pods am-agents-prod ==="
kubectl -n am-agents-prod get pods --no-headers
echo "=== PROD Argo agent apps ==="
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-platform.yaml
kubectl -n argocd get app -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,NS:.spec.destination.namespace' --no-headers | grep -E 'agent|gateway|mcp|fin|qa|tool|db|mkt|support|ai' || true
