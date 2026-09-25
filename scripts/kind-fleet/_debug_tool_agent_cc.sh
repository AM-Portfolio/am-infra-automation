#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
POD=$(kubectl -n am-agents-prod get pods -l app.kubernetes.io/instance=am-tool-agent-prod -o jsonpath='{.items[0].metadata.name}')
echo "POD=$POD"
kubectl -n am-agents-prod describe pod "$POD" 2>&1 | grep -A8 -E 'FailedMount|Warning|Events:' | tail -50
echo "=== SPC paths ==="
kubectl -n am-agents-prod get secretproviderclass am-tool-agent-prod-vault-secrets -o jsonpath='{.spec.parameters.objects}' | python3 -c '
import sys,yaml
objs=yaml.safe_load(sys.stdin.read()) or []
for o in objs:
  print(o.get("objectName"), "->", o.get("secretPath"), "key=", o.get("secretKey"))
'
echo "=== wave ==="
pgrep -af wave_4g || echo no_wave
tail -12 /tmp/wave_4g.log 2>/dev/null || true
echo "=== agents pods ==="
kubectl -n am-agents-prod get pods --no-headers 2>/dev/null | head -30
