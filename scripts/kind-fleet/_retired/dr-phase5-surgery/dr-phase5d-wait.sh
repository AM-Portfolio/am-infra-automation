#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml

sleep 45
echo "=== pods ==="
kubectl get pods -n am-apps-dr

echo "=== identity SPC objects head ==="
kubectl get secretproviderclass -n am-apps-dr am-identity-dr-vault-secrets -o jsonpath='{.spec.parameters.objects}' | head -c 500; echo

echo "=== subscription SPC objects head ==="
kubectl get secretproviderclass -n am-apps-dr am-subscription-dr-vault-secrets -o jsonpath='{.spec.parameters.objects}' | head -c 600; echo

echo "=== notification SPC objects head ==="
kubectl get secretproviderclass -n am-apps-dr am-notification-dr-vault-secrets -o jsonpath='{.spec.parameters.objects}' | head -c 600; echo

echo "=== identity logs ==="
kubectl logs -n am-apps-dr deploy/am-identity-dr --tail=30 2>&1 || true

echo "=== subscription logs ==="
kubectl logs -n am-apps-dr deploy/am-subscription-dr --tail=40 2>&1 || true

echo "=== notification logs ==="
kubectl logs -n am-apps-dr deploy/am-notification-dr --tail=40 2>&1 || true

echo "=== smoke ==="
bash /opt/am-infra-automation/scripts/kind-fleet/dr-phase5d-smoke.sh
