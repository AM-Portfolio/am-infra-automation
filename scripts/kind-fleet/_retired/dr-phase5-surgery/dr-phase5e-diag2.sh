#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
POD=$(kubectl get pods -n am-apps-dr -o name | grep market-data | head -1 | cut -d/ -f2)
echo "pod=$POD"
kubectl get pod -n am-apps-dr "$POD" -o jsonpath='{.status.containerStatuses[0].ready} restarts={.status.containerStatuses[0].restartCount}{"\n"}'

echo "=== probe paths ==="
kubectl get pod -n am-apps-dr "$POD" -o jsonpath='{.spec.containers[0].livenessProbe.httpGet.path} {.spec.containers[0].readinessProbe.httpGet.path}{"\n"}'

for path in /actuator/health /actuator/health/liveness /actuator/health/readiness; do
  code=$(kubectl exec -n am-apps-dr "$POD" -- curl -sS -o /tmp/h.json -w '%{http_code}' -m 5 "http://127.0.0.1:8080$path" 2>/dev/null || echo fail)
  echo "--- $path -> $code ---"
  python3 -c "import json;d=json.load(open('/tmp/h.json')); print(json.dumps(d,indent=2)[:2500])" 2>/dev/null || cat /tmp/h.json 2>/dev/null | head -c 500
  echo
done

echo "=== env (redacted) ==="
kubectl exec -n am-apps-dr "$POD" -- printenv | grep -iE 'INFLUX|UPSTOX|UPSTOCK|ZERODHA|KITE|KAFKA|MONGO|REDIS' | while IFS= read -r line; do
  key=${line%%=*}
  val=${line#*=}
  len=${#val}
  pref=$(printf '%s' "$val" | cut -c1-16)
  echo "$key=${pref}...len=${len}"
done

echo "=== started markers ==="
kubectl logs -n am-apps-dr "$POD" --tail=200 2>&1 | grep -iE 'Started |Tomcat started|Application run failed|GapFill|refusing|Accepting|JVM running' | tail -20

echo "=== vault secret files ==="
kubectl exec -n am-apps-dr "$POD" -- ls /mnt/secrets-store 2>/dev/null | head -40 || true
