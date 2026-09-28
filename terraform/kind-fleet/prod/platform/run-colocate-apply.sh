#!/bin/bash
set -euo pipefail
LOG=/data/am-state/terraform/prod/platform/colocate-apply.log
PLAN=/data/am-state/terraform/prod/platform/colocate.tfplan
docker run --rm --privileged --pid=host \
  alpine:3.20 \
  nsenter -t 1 -m -u -i -n -p -- \
  bash -lc "cd /home/am-ops/src/am-infra-automation/terraform/kind-fleet/prod/platform && terraform apply -input=false -no-color '$PLAN' > '$LOG' 2>&1; echo APPLY_EXIT:\$? >> '$LOG'"
echo HOST_DONE
tail -60 "$LOG"
grep -E '^(Apply complete|Error:|APPLY_EXIT)' "$LOG" || true
kind get clusters
curl -sS -o /dev/null -w 'auth:%{http_code}\n' https://auth.asrax.in/realms/am-realm/.well-known/openid-configuration || true
