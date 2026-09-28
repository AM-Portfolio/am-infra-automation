#!/usr/bin/env bash
set -euo pipefail
for i in $(seq 1 60); do
  if ! pgrep -x terraform >/dev/null 2>&1; then
    echo TF_DONE
    grep -E 'Error:|Apply complete' /tmp/dr-platform-apply.log | tail -30
    tail -40 /tmp/dr-platform-apply.log
    exit 0
  fi
  echo "t=$(date -u +%H:%M:%S) still running lines=$(wc -l </tmp/dr-platform-apply.log)"
  sleep 30
done
echo TIMEOUT
tail -40 /tmp/dr-platform-apply.log
exit 2
