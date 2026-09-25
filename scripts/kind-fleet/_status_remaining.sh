#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-platform.yaml
echo "=== ARGO apps not Synced/Healthy ==="
kubectl -n argocd get applications -l am.asrax.in/env=prod -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' --no-headers 2>/dev/null | awk '$2!="Synced" || $3!="Healthy" {print}' | head -60
echo "=== count ==="
kubectl -n argocd get applications -l am.asrax.in/env=prod --no-headers 2>/dev/null | wc -l
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
echo "=== images :latest ==="
kubectl get deploy -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.template.spec.containers[*]}{.image}{"\n"}{end}{end}' 2>/dev/null | grep ':latest' | grep -E 'am-apps-prod|am-agents-prod' || true
echo "=== QA ingress ==="
kubectl -n am-agents-prod get ingress -o wide 2>/dev/null | head -20
kubectl -n am-agents-prod get ingress am-qa-agents-prod -o yaml 2>/dev/null | head -80
