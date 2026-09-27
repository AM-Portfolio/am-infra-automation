#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
POD=$(kubectl get pods -n am-apps-dr -o name | grep market-data | head -1 | cut -d/ -f2)
kubectl exec -n am-apps-dr "$POD" -- curl -sS -m 8 http://127.0.0.1:8080/actuator/health > /tmp/mkt-health.json
python3 <<'PY'
import json
d=json.load(open("/tmp/mkt-health.json"))
print(json.dumps(d, indent=2)[:8000])
PY
echo "--- recent logs ---"
kubectl logs -n am-apps-dr "$POD" --tail=40 2>&1 | grep -iE 'upstox|upstock|readiness|health|error|Exception|Invalid|token|fail' || kubectl logs -n am-apps-dr "$POD" --tail=20
