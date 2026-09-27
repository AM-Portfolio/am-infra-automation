#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml

echo "=== identity events ==="
kubectl describe pod -n am-apps-dr -l app.kubernetes.io/instance=am-identity-dr 2>/dev/null | tail -40 || \
  kubectl get pods -n am-apps-dr -o name | grep identity | head -1 | xargs -I{} kubectl describe -n am-apps-dr {} | tail -50

echo "=== subscription logs ==="
kubectl logs -n am-apps-dr -l app.kubernetes.io/name=am-subscription --tail=40 2>&1 || \
  kubectl logs -n am-apps-dr deploy/am-subscription-dr --tail=40 2>&1 || true

echo "=== notification logs ==="
kubectl logs -n am-apps-dr deploy/am-notification-dr --tail=40 2>&1 || true

echo "=== SPC ==="
kubectl get secretproviderclass -n am-apps-dr | grep -iE 'identity|subscription|notification' || true
