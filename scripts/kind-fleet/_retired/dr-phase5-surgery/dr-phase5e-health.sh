#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
POD=$(kubectl get pods -n am-apps-dr -o name | grep market-data | head -1 | cut -d/ -f2)
echo "pod=$POD ready=$(kubectl get pod -n am-apps-dr $POD -o jsonpath='{.status.containerStatuses[0].ready}')"
kubectl exec -n am-apps-dr "$POD" -- curl -sS -m 8 http://127.0.0.1:8080/actuator/health > /tmp/mkt-health.json 2>/dev/null || true
python3 <<'PY'
import json
try:
  d=json.load(open("/tmp/mkt-health.json"))
except Exception as e:
  print("no health json", e); raise SystemExit
print("status", d.get("status"))
for k,v in sorted((d.get("components") or {}).items()):
  st=v.get("status") if isinstance(v,dict) else v
  print(f"  {k}: {st}")
  if isinstance(v,dict) and v.get("status") not in ("UP","UNKNOWN",None):
    det=v.get("details") or {}
    if det: print("   details", str(det)[:200])
PY

# look for seed tokens
ls /data/am-state/seed/disaster-latest 2>/dev/null | head
find /data/am-state/seed -iname '*market*' -o -iname '*upstox*' 2>/dev/null | head -20
