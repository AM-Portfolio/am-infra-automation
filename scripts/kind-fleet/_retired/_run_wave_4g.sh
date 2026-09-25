#!/bin/bash
set -euo pipefail
export PYTHONUNBUFFERED=1
pkill -f wave_4g_sync.py 2>/dev/null || true
echo SKIP_QA_DB_SCHEMA
nohup python3 -u /tmp/wave_4g_sync.py /tmp/gitops-prod --start-from am-fin-agent-prod > /tmp/wave_4g.log 2>&1 &
echo PID=\$!
sleep 4
head -35 /tmp/wave_4g.log
