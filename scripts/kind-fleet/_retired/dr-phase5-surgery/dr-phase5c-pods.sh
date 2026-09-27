#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
echo "=== pods ==="
kubectl get pods -n am-apps-dr -o wide
kubectl get pods -n am-agents-dr -o wide
echo "=== describe failing ==="
for p in $(kubectl get pods -n am-apps-dr --no-headers 2>/dev/null | awk '$3!~/Running|Completed/{print $1}'); do
  echo "--- $p ---"
  kubectl describe pod -n am-apps-dr "$p" 2>&1 | tail -25
done
for p in $(kubectl get pods -n am-agents-dr --no-headers 2>/dev/null | awk '$3!~/Running|Completed/{print $1}'); do
  echo "--- agents/$p ---"
  kubectl describe pod -n am-agents-dr "$p" 2>&1 | tail -25
done
echo "=== curl am-dr ==="
curl -sS -o /tmp/amdr.body -w "%{http_code}" -m 15 https://am-dr.asrax.in/ || echo curl_fail
echo
head -c 200 /tmp/amdr.body 2>/dev/null; echo
