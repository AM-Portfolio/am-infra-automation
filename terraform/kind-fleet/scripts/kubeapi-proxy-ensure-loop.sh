#!/bin/bash
# Runs inside am-kubeapi-proxy-ensure (host Docker, --restart always).
# Rewrites kubeconfig to Kind control-plane Docker DNS, then keeps kubeapi-proxy applied.
set -euo pipefail

INTERVAL="${INTERVAL:-30}"
APPS_CP="${APPS_CP:?APPS_CP required}"
MANIFEST="${MANIFEST:-/manifests/kubeapi-proxy.yaml}"
export KUBECONFIG=/tmp/kubeconfig

rewrite_kc() {
  # Prefer server https://<control-plane>:6443 on the kind Docker network.
  sed -E "s#(server:[[:space:]]*)https?://[^[:space:]]+#\1https://${APPS_CP}:6443#" \
    /kubeconfig.host > /tmp/kubeconfig
  echo "kubeconfig -> https://${APPS_CP}:6443"
}

rewrite_kc
echo "am-kubeapi-proxy-ensure loop interval=${INTERVAL}s apps_cp=${APPS_CP}"

while true; do
  if ! kubectl get --raw=/readyz >/dev/null 2>&1; then
    echo "$(date -u +%FT%TZ) api not ready; rewrite + wait"
    rewrite_kc
    sleep 10
    continue
  fi
  ready="$(kubectl -n infra get deploy kubeapi-proxy -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
  if [[ "${ready:-0}" != "1" ]]; then
    echo "$(date -u +%FT%TZ) applying kubeapi-proxy (ready=${ready:-0})"
    kubectl apply -f "$MANIFEST" || true
    kubectl -n infra rollout status deploy/kubeapi-proxy --timeout=60s || true
  else
    echo "$(date -u +%FT%TZ) kubeapi-proxy ready=1"
  fi
  sleep "$INTERVAL"
done
