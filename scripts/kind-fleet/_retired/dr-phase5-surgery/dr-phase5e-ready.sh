#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml

POD=$(kubectl get pods -n am-apps-dr -o name | grep market-data | head -1 | cut -d/ -f2)
echo "pod=$POD"
kubectl get pod -n am-apps-dr "$POD" -o wide
kubectl get pod -n am-apps-dr "$POD" -o json > /tmp/mkt-pod.json
python3 <<'PY'
import json
p=json.load(open("/tmp/mkt-pod.json"))
print("phase", p["status"].get("phase"))
for c in p["status"].get("conditions") or []:
  print("cond", c.get("type"), c.get("status"), c.get("reason"), (c.get("message") or "")[:160])
for c in p["status"].get("containerStatuses") or []:
  print("ctr", c["name"], "ready=", c["ready"], "restarts=", c.get("restartCount"), "state=", c.get("state"))
  print("  lastState=", c.get("lastState"))
spec=p["spec"]["containers"][0]
print("readiness", spec.get("readinessProbe"))
print("liveness", spec.get("livenessProbe"))
print("startup", spec.get("startupProbe"))
PY

echo "=== recent log lines (filtered) ==="
kubectl logs -n am-apps-dr "$POD" --tail=200 2>&1 | grep -iE 'Started|ERROR|Exception|Failed|Tomcat|actuator|health|Caused by|WARN.*[Ff]ail' | tail -40

echo "=== in-cluster health ==="
kubectl exec -n am-apps-dr "$POD" -- wget -qO- -T 5 http://127.0.0.1:8080/actuator/health 2>&1 | head -c 300 || \
kubectl exec -n am-apps-dr "$POD" -- curl -sS -m 5 http://127.0.0.1:8080/actuator/health 2>&1 | head -c 300 || true
echo
