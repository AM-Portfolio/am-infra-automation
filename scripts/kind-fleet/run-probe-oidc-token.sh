#!/usr/bin/env bash
set -euo pipefail
ENV="${1:-prod}"
KCFG="${KUBECONFIG:-/data/am-state/kubeconfig.am-${ENV}-infra.yaml}"
pkill -f "port-forward.*keycloak.*18080" 2>/dev/null || true
kubectl --kubeconfig "$KCFG" -n identity port-forward svc/keycloak 18080:8080 >/tmp/kc-pf-tok.log 2>&1 &
PF=$!
cleanup() { kill "$PF" 2>/dev/null || true; }
trap cleanup EXIT
for i in $(seq 1 40); do
  curl -sf --max-time 1 http://127.0.0.1:18080/ >/dev/null 2>&1 && break
  sleep 1
done
export KC_BASE=http://127.0.0.1:18080
python3 /tmp/_probe_oidc_token_claims.py "$ENV"
