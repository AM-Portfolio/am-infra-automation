#!/usr/bin/env bash
# Phase 4: vault-apps seed + apps G25 CSI on VPS3.
# NEVER kind delete — if G1 already created am-dr-apps, terraform import (adopt).
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export AM_OPS_REAL_KIND=/usr/local/libexec/am-real/kind
export AM_OPS_REAL_KUBECTL=/usr/local/libexec/am-real/kubectl

ROOT=/opt/am-infra-automation/terraform/kind-fleet
STATE_VA=/data/am-state/terraform/dr/vault-apps
STATE_APPS=/data/am-state/terraform/dr/apps
ADOPT="${ADOPT:-/opt/am-infra-automation/scripts/kind-fleet/adopt-kind-cluster.sh}"
# Fallback when script not yet synced to /opt
[[ -x "$ADOPT" ]] || ADOPT="$(cd "$(dirname "$0")" && pwd)/adopt-kind-cluster.sh"

mkdir -p "$STATE_VA" "$STATE_APPS" /data/am-state/credentials /home/am-ops/.asrax
chown -R am-ops:am-ops /data/am-state/terraform/dr/vault-apps /data/am-state/terraform/dr/apps 2>/dev/null || true

echo "=== prereq files ==="
test -f /data/am-state/credentials/dr-keycloak-admin.env
test -f /data/am-state/credentials/dr-infra-stores.env
test -f /data/am-state/vault-dr-infra.json

echo "=== vault-apps init+apply ==="
cd "$ROOT/dr/vault-apps"
terraform init -backend-config=backend.hcl -input=false -reconfigure
terraform apply -auto-approve -input=false | tee /tmp/dr-vault-apps-apply.log
echo "vault-apps service_count=$(terraform output -raw service_count 2>/dev/null || true)"

echo "=== apps init + adopt (no delete) ==="
cd "$ROOT/dr/apps"
terraform init -backend-config=backend.hcl -input=false -reconfigure
bash "$ADOPT" am-dr-apps

echo "=== apps apply (G25) ==="
nohup terraform apply -auto-approve -input=false > /tmp/dr-apps-apply.log 2>&1 &
echo APPS_TF_PID=$!
echo "apps apply started; log /tmp/dr-apps-apply.log"
