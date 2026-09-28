#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:$PATH
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml

echo "=== novu apply ==="
pgrep -af 'terraform apply' || echo TF_IDLE
grep -E 'Error:|Apply complete' /tmp/dr-novu-apply.log 2>/dev/null | tail -20 || true
tail -15 /tmp/dr-novu-apply.log 2>/dev/null || true

echo "=== novu pods ==="
kubectl get pods -n notification 2>&1 || true

echo "=== platform summary ==="
kubectl get pods -A --no-headers 2>/dev/null | awk '$4!="Running" && $4!="Completed" {print}' | head -30 || true

echo "=== vault-apps tree ==="
ls /opt/am-infra-automation/terraform/kind-fleet/dr/vault-apps 2>&1 | head -20
ls /data/am-state/terraform/dr/ 2>&1
