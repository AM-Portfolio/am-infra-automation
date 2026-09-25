#!/bin/bash
set -euo pipefail
export PYTHONUNBUFFERED=1
export GITOPS_REV="${GITOPS_REV:-fix/https-base-urls-no-ports}"

rm -rf /tmp/gitops-prod
mkdir -p /tmp/gitops-prod
tar -xzf /tmp/gitops-prod.tgz -C /tmp/gitops-prod
# tarball contains prod/ + projects/ at top of gitops-prod
test -f /tmp/gitops-prod/prod/agents/am-qa-agents.yaml
ls /tmp/gitops-prod/prod/agents | head

pkill -f closout_sync_remaining.py 2>/dev/null || true
sleep 1
nohup env GITOPS_REV="$GITOPS_REV" python3 -u /tmp/closout_sync_remaining.py > /tmp/closout_sync.log 2>&1 &
echo "PID=$! GITOPS_REV=$GITOPS_REV"
sleep 4
head -50 /tmp/closout_sync.log
