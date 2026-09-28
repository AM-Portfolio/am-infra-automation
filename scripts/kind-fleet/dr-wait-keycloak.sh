#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:$PATH
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml

for i in $(seq 1 24); do
  kubectl get pods -n identity -o wide || true
  READY=$(kubectl get pod -n identity keycloak-0 -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo false)
  echo "t=$i ready=$READY"
  if [ "$READY" = "true" ]; then
    echo KEYCLOAK_READY
    break
  fi
  kubectl logs -n identity keycloak-0 --tail=12 2>&1 | tail -12 || true
  sleep 15
done

echo "=== terraform ==="
pgrep -af 'terraform apply' || echo none
grep -E 'Error:|Apply complete' /tmp/dr-platform-apply.log | tail -20 || true
tail -8 /tmp/dr-platform-apply.log || true
