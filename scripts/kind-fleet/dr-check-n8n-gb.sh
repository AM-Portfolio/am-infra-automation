#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:$PATH
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml

echo "=== pods ==="
kubectl get pods -n n8n -o wide 2>&1 || true
kubectl get pods -n growthbook -o wide 2>&1 || true

echo "=== n8n logs ==="
kubectl logs -n n8n -l app.kubernetes.io/name=n8n --tail=50 2>&1 | tail -50 || \
  kubectl logs -n n8n --all-containers --tail=50 2>&1 | tail -50 || true
kubectl describe pods -n n8n 2>&1 | tail -30 || true

echo "=== growthbook logs ==="
kubectl logs -n growthbook --all-containers --tail=60 2>&1 | tail -60 || true
kubectl describe pods -n growthbook 2>&1 | tail -40 || true

echo "=== events ==="
kubectl get events -n n8n --sort-by='.lastTimestamp' 2>/dev/null | tail -15
kubectl get events -n growthbook --sort-by='.lastTimestamp' 2>/dev/null | tail -15
