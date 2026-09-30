#!/usr/bin/env bash
# Host Docker ensure for kubeapi-proxy (port-exposer pattern).
# Survives Kind recreate: container --restart always waits for API then applies.
#
# Usage:
#   ./ensure-kubeapi-proxy.sh dig
#   ENV=prod ./ensure-kubeapi-proxy.sh
#   ./ensure-kubeapi-proxy.sh prod
set -euo pipefail

ENV_NAME="${1:-${ENV:-dig}}"
case "$ENV_NAME" in
  dig|dev) ENV_NAME=dig; APPS_CP="am-dev-apps-control-plane"; KC_NAME="kubeconfig.dev" ;;
  preprod) APPS_CP="am-preprod-apps-control-plane"; KC_NAME="kubeconfig.preprod" ;;
  prod) APPS_CP="am-prod-apps-control-plane"; KC_NAME="kubeconfig.am-prod-apps.yaml" ;;
  dr) APPS_CP="am-dr-apps-control-plane"; KC_NAME="kubeconfig.am-dr-apps.yaml" ;;
  *) echo "ENV must be dig|dev|preprod|prod|dr (got: $ENV_NAME)" >&2; exit 1 ;;
esac

ASRAX_HOME="${ASRAX_HOME:-${HOME:-/root}/.asrax}"
KC_HOST=""
for cand in \
  "${ASRAX_HOME}/${KC_NAME}" \
  "${ASRAX_HOME}/kubeconfig.${ENV_NAME}" \
  "${ASRAX_HOME}/kubeconfig.dev"; do
  if [[ -f "$cand" ]]; then
    KC_HOST="$cand"
    break
  fi
done
if [[ -z "$KC_HOST" ]]; then
  echo "ERROR: no kubeconfig under ${ASRAX_HOME} for ${ENV_NAME}" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOOP_SH="${SCRIPT_DIR}/kubeapi-proxy-ensure-loop.sh"
MANIFEST="${MANIFEST:-$(cd "${SCRIPT_DIR}/../../modules/ops/kubeapi-proxy" && pwd)/kubeapi-proxy.yaml}"
if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: missing kubeapi-proxy.yaml at $MANIFEST" >&2
  exit 1
fi
if [[ ! -f "$LOOP_SH" ]]; then
  echo "ERROR: missing $LOOP_SH" >&2
  exit 1
fi

ENSURE_NAME="${ENSURE_NAME:-am-kubeapi-proxy-ensure}"
INTERVAL="${INTERVAL:-30}"
WAIT_SECS="${WAIT_SECS:-600}"
IMAGE="${KUBECTL_IMAGE:-alpine/k8s:1.31.4}"

echo "== ensure-kubeapi-proxy ENV=$ENV_NAME APPS_CP=$APPS_CP =="

deadline=$((SECONDS + WAIT_SECS))
echo "wait Kind node $APPS_CP (upto ${WAIT_SECS}s)"
while (( SECONDS < deadline )); do
  if docker inspect "$APPS_CP" >/dev/null 2>&1; then
    echo "kind node present"
    break
  fi
  sleep 5
done
if ! docker inspect "$APPS_CP" >/dev/null 2>&1; then
  echo "ERROR: $APPS_CP not found within ${WAIT_SECS}s" >&2
  exit 1
fi

docker rm -f "$ENSURE_NAME" 2>/dev/null || true

docker run -d --name "$ENSURE_NAME" \
  --restart always \
  --network kind \
  -e APPS_CP="$APPS_CP" \
  -e INTERVAL="$INTERVAL" \
  -e MANIFEST=/manifests/kubeapi-proxy.yaml \
  -v "${KC_HOST}:/kubeconfig.host:ro" \
  -v "${MANIFEST}:/manifests/kubeapi-proxy.yaml:ro" \
  -v "${LOOP_SH}:/ensure-loop.sh:ro" \
  --entrypoint /bin/bash \
  "$IMAGE" \
  /ensure-loop.sh

sleep 3
st=$(docker inspect -f '{{.State.Running}}' "$ENSURE_NAME" 2>/dev/null || echo false)
if [[ "$st" != "true" ]]; then
  echo "ERROR: $ENSURE_NAME failed to stay up" >&2
  docker logs "$ENSURE_NAME" 2>&1 | tail -40 || true
  exit 1
fi
echo "$ENSURE_NAME up (restart=always) — will apply kubeapi-proxy when Kind is ready"
