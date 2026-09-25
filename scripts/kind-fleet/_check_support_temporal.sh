#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
echo "=== SPC TEMPORAL ==="
kubectl -n am-agents-prod get secretproviderclass am-support-agent-vault-secrets -o jsonpath='{.spec.parameters.objects}' | python3 -c '
import sys,re
t=sys.stdin.read()
for m in re.finditer(r"objectName: \"([^\"]*TEMPORAL[^\"]*)\"[\s\S]*?secretKey: \"([^\"]+)\"", t):
  print(m.group(1), "->", m.group(2))
print("HOST_IN_SPC", "TEMPORAL_HOST" in t)
'
echo "=== SYNCED SECRET KEYS (temporal) ==="
kubectl -n am-agents-prod get secret am-support-agent-synced-secrets -o json | python3 -c '
import json,sys,base64
d=json.load(sys.stdin).get("data") or {}
for k in sorted(d):
  if "TEMPORAL" in k.upper():
    v=base64.b64decode(d[k]).decode("utf-8","replace")
    print(k, "=", v[:80])
'
echo "=== WORKER PODS ==="
kubectl -n am-agents-prod get pods -l app.kubernetes.io/component=worker,app.kubernetes.io/instance=am-support-agent-prod -o wide
POD=$(kubectl -n am-agents-prod get pods -l app.kubernetes.io/component=worker,app.kubernetes.io/instance=am-support-agent-prod --field-selector=status.phase!=Succeeded -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
echo "POD=$POD"
if [ -n "$POD" ]; then
  echo "=== hostAliases ==="
  kubectl -n am-agents-prod get pod "$POD" -o jsonpath='{.spec.hostAliases}' ; echo
  echo "=== env TEMPORAL_HOST ==="
  kubectl -n am-agents-prod exec "$POD" -- printenv TEMPORAL_HOST 2>/dev/null || true
  echo "=== logs ==="
  kubectl -n am-agents-prod logs "$POD" --tail=25 2>&1 | grep -vE 'password|secret|token' || true
  kubectl -n am-agents-prod logs "$POD" --previous --tail=25 2>&1 | grep -vE 'password|secret|token' || true
fi
