#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml

echo "=== identity SPC ==="
kubectl get secretproviderclass -n am-apps-dr am-identity-dr-vault-secrets -o yaml

echo "=== gateway SPC (working sample) ==="
kubectl get secretproviderclass -n am-apps-dr am-gateway-dr-vault-secrets -o yaml | sed -n '1,80p'

echo "=== notification SPC ==="
kubectl get secretproviderclass -n am-apps-dr am-notification-dr-vault-secrets -o yaml | sed -n '1,100p'

echo "=== subscription pod status ==="
kubectl get pods -n am-apps-dr | grep -iE 'subscription|notification|identity'
kubectl logs -n am-apps-dr deploy/am-subscription-dr --tail=30 2>&1 || true
