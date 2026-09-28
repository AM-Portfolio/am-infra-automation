#!/usr/bin/env bash
set -euo pipefail
cd /home/am-ops/src/am-infra-automation/terraform/kind-fleet/prod/stores
terraform init -input=false -upgrade >/tmp/tf-stores-init2.log 2>&1 || {
  tail -60 /tmp/tf-stores-init2.log
  exit 1
}
echo "=== plan ==="
terraform plan -input=false -target=module.vault -target=module.minio -out=/tmp/stores-oidc.plan 2>&1 | tee /tmp/tf-stores-plan3.log | tail -150
echo "=== apply ==="
terraform apply -input=false /tmp/stores-oidc.plan 2>&1 | tee /tmp/tf-stores-apply.log | tail -80
