#!/bin/bash
set -euo pipefail
pkill -f '/tmp/wave_4g_sync.py' 2>/dev/null || true
sleep 1
nohup python3 -u /tmp/wave_4g_sync.py /tmp/gitops-prod --start-from am-mkt-agents-prod > /tmp/wave_4g.log 2>&1 &
echo "PID=$!"
sleep 5
head -60 /tmp/wave_4g.log
pgrep -af '/tmp/wave_4g_sync.py' || echo no_python_wave
