#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:$PATH
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml

echo "=== terraform procs ==="
pgrep -af terraform || echo none

echo "=== apply log ==="
if [ -f /tmp/dr-platform-apply.log ]; then
  grep -E 'Error:|Apply complete' /tmp/dr-platform-apply.log | tail -20 || true
  echo "--- tail ---"
  tail -25 /tmp/dr-platform-apply.log
else
  echo "no log"
fi

echo "=== keycloak ==="
kubectl get pods -n identity || true
helm list -n identity || true
