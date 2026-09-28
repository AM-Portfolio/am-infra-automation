#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:$PATH
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml

echo "=== pods temporal/openproject ==="
kubectl get pods -A | grep -iE 'temporal|openproject|NAME' || true

echo "=== temporal describe ==="
kubectl get pods -n temporal -o wide 2>/dev/null || true
for p in $(kubectl get pods -n temporal -o name 2>/dev/null); do
  echo "--- logs $p ---"
  kubectl logs -n temporal "$p" --tail=40 2>&1 || true
  kubectl describe -n temporal "$p" 2>&1 | tail -25
done

echo "=== openproject ==="
kubectl get pods -n openproject -o wide 2>/dev/null || true
for p in $(kubectl get pods -n openproject -o name 2>/dev/null); do
  echo "--- logs $p ---"
  kubectl logs -n openproject "$p" --tail=40 2>&1 || true
  kubectl describe -n openproject "$p" 2>&1 | tail -25
done

echo "=== events ==="
kubectl get events -n temporal --sort-by='.lastTimestamp' 2>/dev/null | tail -20
kubectl get events -n openproject --sort-by='.lastTimestamp' 2>/dev/null | tail -20

echo "=== dns/pg from platform ==="
docker exec am-dr-platform-control-plane getent ahostsv4 postgres-dr.asrax.in || true
docker exec am-dr-platform-control-plane bash -c 'timeout 3 bash -c "</dev/tcp/postgres-dr.asrax.in/5432" && echo pg_ok || echo pg_fail'

echo "=== terraform ==="
pgrep -af 'terraform apply' || echo TF_IDLE
grep -E 'Error:|Apply complete|temporal|openproject' /tmp/dr-platform-apply.log 2>/dev/null | tail -40 || true
