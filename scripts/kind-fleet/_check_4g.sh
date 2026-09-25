#!/bin/bash
set -euo pipefail
echo "=== tail ==="
tail -50 /tmp/wave_4g.log || true
echo "=== markers ==="
grep -E 'READY|WAVE_4G|sync failed|deploy not|timeout|SystemExit|Error' /tmp/wave_4g.log || true
echo "=== proc ==="
pgrep -af wave_4g_sync || echo PROC_GONE
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
echo "=== apps pods ==="
kubectl -n am-apps-prod get pods --no-headers 2>/dev/null | awk '{print $1,$2,$3}' | head -40
echo "=== agents pods ==="
kubectl -n am-agents-prod get pods --no-headers 2>/dev/null | awk '{print $1,$2,$3}' | head -40
