#!/bin/bash
set -euo pipefail
LOGDIR=/data/am-state/terraform/prod/platform
# Run host terraform as root via nsenter (am-ops has docker, no sudo).
docker run --rm --privileged --pid=host \
  alpine:3.20 \
  nsenter -t 1 -m -u -i -n -p -- \
  bash -lc 'cd /home/am-ops/src/am-infra-automation/terraform/kind-fleet/prod/platform && terraform init -backend-config=backend.hcl -input=false > /data/am-state/terraform/prod/platform/colocate-init.log 2>&1; echo INIT_EXIT:$? >> /data/am-state/terraform/prod/platform/colocate-init.log; terraform plan -input=false -no-color -out=/data/am-state/terraform/prod/platform/colocate.tfplan > /data/am-state/terraform/prod/platform/colocate-plan.log 2>&1; echo PLAN_EXIT:$? >> /data/am-state/terraform/prod/platform/colocate-plan.log'
echo HOST_DONE
grep -E '^(Plan:|Error:|PLAN_EXIT|Warning:)' "$LOGDIR/colocate-plan.log" | head -40 || true
tail -30 "$LOGDIR/colocate-plan.log"
