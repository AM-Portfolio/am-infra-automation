#!/usr/bin/env bash
# Ensure Vault→kube GHCR pull-secret sync CronJob is present on apps cluster.
#
# Usage (root on Contabo VPS, or laptop with kubeconfig.prod → prod-apps):
#   ENV=prod bash ensure-ghcr-pull-secrets.sh
#   bash ensure-ghcr-pull-secrets.sh prod
#
# Optional seed when Vault path empty and credentials.env is available:
#   SEED_IF_MISSING=1 bash ensure-ghcr-pull-secrets.sh prod
set -euo pipefail

ENV_NAME="${1:-${ENV:-prod}}"
case "$ENV_NAME" in
  prod|dr|preprod|dev) ;;
  *) echo "ENV must be prod|dr|preprod|dev (got: $ENV_NAME)" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
# scripts/kind-fleet → repo root is two up from terraform/kind-fleet/scripts
if [[ -d "$ROOT/../../../scripts/kind-fleet" ]]; then
  SCRIPTS="$(cd "$ROOT/../../../scripts/kind-fleet" && pwd)"
  MANIFEST_DIR="$(cd "$ROOT/../manifests/ghcr-pull-sync" && pwd)"
else
  # invoked from scripts/kind-fleet copy
  SCRIPTS="$ROOT"
  MANIFEST_DIR="$(cd "$ROOT/../../terraform/kind-fleet/manifests/ghcr-pull-sync" && pwd)"
fi

ASRAX_HOME="${ASRAX_HOME:-${HOME:-/root}/.asrax}"
APPS_NS="am-apps-${ENV_NAME}"
[[ "$ENV_NAME" == "prod" ]] && APPS_NS="am-apps-prod"
[[ "$ENV_NAME" == "dr" ]] && APPS_NS="am-apps-dr"

MANIFEST="${MANIFEST_DIR}/${ENV_NAME}.yaml"
if [[ ! -f "$MANIFEST" ]]; then
  # fall back to prod template with note
  MANIFEST="${MANIFEST_DIR}/prod.yaml"
fi
[[ -f "$MANIFEST" ]] || { echo "ERROR: missing manifest $MANIFEST" >&2; exit 1; }

echo "== ensure-ghcr-pull-secrets ENV=$ENV_NAME =="

# Prefer ASRAX kubeconfig for apps when present on VPS
if [[ -f "$ASRAX_HOME/kubeconfig.am-${ENV_NAME}-apps.yaml" ]]; then
  export KUBECONFIG="${KUBECONFIG:-$ASRAX_HOME/kubeconfig.am-${ENV_NAME}-apps.yaml}"
elif [[ -f "/data/am-state/kubeconfig.am-${ENV_NAME}-apps.yaml" ]]; then
  export KUBECONFIG="${KUBECONFIG:-/data/am-state/kubeconfig.am-${ENV_NAME}-apps.yaml}"
fi

if [[ "${SEED_IF_MISSING:-0}" == "1" ]]; then
  echo "== seed Vault apps/${ENV_NAME}/infra/ghcr if missing =="
  # Needs infra context — best-effort
  if command -v python3 >/dev/null 2>&1 && [[ -f "$SCRIPTS/seed-vault-ghcr.py" ]]; then
    (
      # switch to infra kubeconfig when available
      if [[ -f "$ASRAX_HOME/kubeconfig.am-${ENV_NAME}-infra.yaml" ]]; then
        export KUBECONFIG="$ASRAX_HOME/kubeconfig.am-${ENV_NAME}-infra.yaml"
      elif [[ -f "/data/am-state/kubeconfig.am-${ENV_NAME}-infra.yaml" ]]; then
        export KUBECONFIG="/data/am-state/kubeconfig.am-${ENV_NAME}-infra.yaml"
      fi
      python3 "$SCRIPTS/seed-vault-ghcr.py" --env "$ENV_NAME" || echo "WARN: seed-vault-ghcr failed (continue)"
    )
  else
    echo "WARN: seed script unavailable"
  fi
fi

echo "== apply $MANIFEST =="
kubectl apply -f "$MANIFEST"

# Re-run bootstrap Job (delete stale once-job)
echo "== trigger sync Job =="
kubectl -n "$APPS_NS" delete job ghcr-pull-secret-sync-once --ignore-not-found=true
# Job is in the manifest — re-apply creates it after delete
kubectl apply -f "$MANIFEST"

echo "== wait Job =="
kubectl -n "$APPS_NS" wait --for=condition=complete job/ghcr-pull-secret-sync-once --timeout=180s \
  || kubectl -n "$APPS_NS" logs -l job-name=ghcr-pull-secret-sync-once --tail=50 || true

echo "ensure-ghcr-pull-secrets DONE ENV=$ENV_NAME"
