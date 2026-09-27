#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml

# wait for pod Running
for i in $(seq 1 30); do
  POD=$(kubectl get pods -n am-apps-dr -o name 2>/dev/null | grep market-data | head -1 | cut -d/ -f2 || true)
  [ -n "$POD" ] || { sleep 2; continue; }
  phase=$(kubectl get pod -n am-apps-dr "$POD" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  ready=$(kubectl get pod -n am-apps-dr "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || true)
  echo "try=$i pod=$POD phase=$phase ready=$ready"
  if [ "$phase" = "Running" ]; then
    # wait until port answers
    if kubectl exec -n am-apps-dr "$POD" -- curl -sS -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/actuator/health >/tmp/code 2>/dev/null; then
      break
    fi
  fi
  sleep 5
done

POD=$(kubectl get pods -n am-apps-dr -o name | grep market-data | head -1 | cut -d/ -f2)
echo "using $POD"
kubectl get pod -n am-apps-dr "$POD" -o wide

echo "=== probes ==="
kubectl get pod -n am-apps-dr "$POD" -o json | python3 -c '
import json,sys
p=json.load(sys.stdin)["spec"]["containers"][0]
for k in ("livenessProbe","readinessProbe","startupProbe"):
  pr=p.get(k)
  print(k, pr)
'

for path in /health /actuator/health /actuator/health/liveness /actuator/health/readiness; do
  out=$(kubectl exec -n am-apps-dr "$POD" -- curl -sS -m 8 -w "\nHTTP:%{http_code}" "http://127.0.0.1:8080$path" 2>&1 || true)
  echo "=== $path ==="
  echo "$out" | tail -c 3000
  echo
done

echo "=== env redacted ==="
kubectl exec -n am-apps-dr "$POD" -- printenv 2>/dev/null | grep -iE 'INFLUX|UPSTOX|UPSTOCK|ZERODHA|KITE|KAFKA' | while IFS= read -r line; do
  key=${line%%=*}
  val=${line#*=}
  pref=$(printf '%s' "$val" | cut -c1-20)
  echo "$key=${pref}...len=${#val}"
done

echo "=== vault files ==="
kubectl exec -n am-apps-dr "$POD" -- sh -c 'ls /mnt/secrets-store 2>/dev/null | head -50'

echo "=== recent start logs ==="
kubectl logs -n am-apps-dr "$POD" --tail=80 2>&1 | grep -iE 'Started |Tomcat|GapFill|Influx|Kafka|UPSTOX|Invalid|fail|ERROR|refusing' | tail -40
