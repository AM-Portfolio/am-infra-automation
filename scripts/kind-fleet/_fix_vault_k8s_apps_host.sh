#!/usr/bin/env bash
# Operator wrapper — delegates to terraform/kind-fleet/scripts/ensure-vault-k8s-apps-auth.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../terraform/kind-fleet/scripts" && pwd)"
# From am-infra-automation/scripts/kind-fleet → ../../terraform/kind-fleet/scripts
if [[ ! -f "$ROOT/ensure-vault-k8s-apps-auth.sh" ]]; then
  ROOT="$(cd "$(dirname "$0")/../../.." && pwd)/terraform/kind-fleet/scripts"
fi
# Prefer sibling in same repo layout when copied under terraform/kind-fleet/scripts
ALT="$(cd "$(dirname "$0")" && pwd)/../../terraform/kind-fleet/scripts/ensure-vault-k8s-apps-auth.sh"
if [[ -f /root/am-repos/am-infra-automation/terraform/kind-fleet/scripts/ensure-vault-k8s-apps-auth.sh ]]; then
  exec bash /root/am-repos/am-infra-automation/terraform/kind-fleet/scripts/ensure-vault-k8s-apps-auth.sh "$@"
fi
if [[ -f "$ROOT/ensure-vault-k8s-apps-auth.sh" ]]; then
  exec bash "$ROOT/ensure-vault-k8s-apps-auth.sh" "$@"
fi
echo "ensure-vault-k8s-apps-auth.sh not found" >&2
exit 1
