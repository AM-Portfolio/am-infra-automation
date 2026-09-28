#!/bin/bash
set -euo pipefail
# Sync fixed keycloak module + continue apply (new plan; prior plan partially applied).
SRC=/home/am-ops/src/am-infra-automation
KC=$SRC/terraform/modules/apps/keycloak
cp /tmp/kc-oidc_clients.tf "$KC/oidc_clients.tf"
cp /tmp/kc-test_users.tf "$KC/test_users.tf"
LOGDIR=/data/am-state/terraform/prod/platform
docker run --rm --privileged --pid=host \
  alpine:3.20 \
  nsenter -t 1 -m -u -i -n -p -- \
  bash -lc "cd /home/am-ops/src/am-infra-automation/terraform/kind-fleet/prod/platform && terraform plan -input=false -no-color -out=/data/am-state/terraform/prod/platform/colocate.tfplan > /data/am-state/terraform/prod/platform/colocate-plan2.log 2>&1; echo PLAN_EXIT:\$? >> /data/am-state/terraform/prod/platform/colocate-plan2.log; terraform apply -input=false -no-color /data/am-state/terraform/prod/platform/colocate.tfplan > /data/am-state/terraform/prod/platform/colocate-apply2.log 2>&1; echo APPLY_EXIT:\$? >> /data/am-state/terraform/prod/platform/colocate-apply2.log"
echo HOST_DONE
grep -E '^(Plan:|Apply complete|Error:|PLAN_EXIT|APPLY_EXIT)' "$LOGDIR/colocate-plan2.log" "$LOGDIR/colocate-apply2.log" 2>/dev/null || true
tail -40 "$LOGDIR/colocate-apply2.log"
kind get clusters
curl -sS -o /dev/null -w 'auth_http:%{http_code}\n' --max-time 15 https://auth.asrax.in/realms/am-realm/.well-known/openid-configuration || echo auth_curl_fail
