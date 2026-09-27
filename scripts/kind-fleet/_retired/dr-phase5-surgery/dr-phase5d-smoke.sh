#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin

echo "=== DNS ==="
getent hosts am-dr.asrax.in || true
getent hosts asrax-dr.asrax.in || true
getent hosts corp-dr.asrax.in || true

echo "=== HTTP ==="
for url in \
  "https://am-dr.asrax.in/" \
  "https://am-dr.asrax.in/gateway" \
  "https://am-dr.asrax.in/identity/actuator/health" \
  "https://auth-dr.asrax.in/"
do
  code=$(curl -sS -o /tmp/am-dr-smoke.body -w "%{http_code}" --connect-timeout 15 -m 30 "$url" || echo ERR)
  echo "$code  $url"
  head -c 160 /tmp/am-dr-smoke.body 2>/dev/null; echo
done

echo "=== Argo identity apps ==="
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml
kubectl -n argocd get applications.argoproj.io \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status \
  | grep -E 'NAME|identity|subscription|notification' || true
