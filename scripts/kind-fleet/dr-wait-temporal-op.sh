#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:$PATH
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml

for i in $(seq 1 18); do
  echo "=== t=$i ==="
  kubectl get pods -n temporal
  kubectl get pods -n openproject
  T_OK=$(kubectl get pods -n temporal --no-headers 2>/dev/null | grep -vE 'Completed|Running' | wc -l)
  O_READY=$(kubectl get pod -n openproject -l app=openproject -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo false)
  # openproject may use different labels
  O_READY=$(kubectl get pods -n openproject -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo false)
  SCHEMA=$(kubectl get jobs -n temporal -o jsonpath='{.items[0].status.succeeded}' 2>/dev/null || echo 0)
  echo "bad_temporal_pods=$T_OK openproject_ready=$O_READY schema_succeeded=$SCHEMA"
  if [ "$T_OK" = "0" ] && [ "$O_READY" = "true" ]; then
    echo ALL_OK
    exit 0
  fi
  # show recent errors
  kubectl logs -n temporal -l 'app.kubernetes.io/component=frontend' --tail=5 2>/dev/null | tail -5 || true
  kubectl logs -n openproject --tail=8 2>/dev/null | grep -iE 'error|ERROR|Listening|started|permission' | tail -8 || true
  sleep 15
done
echo STILL_FAILING
kubectl logs -n temporal -l 'app.kubernetes.io/component=frontend' --tail=20 2>/dev/null || true
kubectl logs -n openproject --tail=30 2>/dev/null | tail -30 || true
exit 1
