#!/usr/bin/env bash
# Run fix-keycloak-oidc-scopes.py against in-cluster Keycloak via port-forward.
set -euo pipefail
ENV="${1:-prod}"
KCFG="${KUBECONFIG:-/data/am-state/kubeconfig.am-${ENV}-infra.yaml}"
CREDS="/data/am-state/credentials/${ENV}/keycloak-admin.env"
SCRIPT="${2:-/tmp/fix-keycloak-oidc-scopes.py}"

test -f "$KCFG"
test -f "$CREDS"
test -f "$SCRIPT"

# Prefer NodePort when present (avoids stale PF / empty root response).
NODE_PORT="$(kubectl --kubeconfig "$KCFG" -n identity get svc keycloak -o jsonpath='{.spec.ports[?(@.port==8080)].nodePort}' 2>/dev/null || true)"
NODE_IP="$(kubectl --kubeconfig "$KCFG" get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)"
KC_URL=""
if [[ -n "${NODE_PORT}" && -n "${NODE_IP}" ]]; then
  KC_URL="http://${NODE_IP}:${NODE_PORT}"
  echo "using NodePort ${KC_URL}"
else
  pkill -f "port-forward.*keycloak.*18080" 2>/dev/null || true
  kubectl --kubeconfig "$KCFG" -n identity port-forward svc/keycloak 18080:8080 >/tmp/kc-pf-scopes.log 2>&1 &
  PF=$!
  cleanup() { kill "$PF" 2>/dev/null || true; }
  trap cleanup EXIT
  KC_URL="http://127.0.0.1:18080"
  echo "using port-forward ${KC_URL}"
fi

ok=0
for i in $(seq 1 60); do
  if curl -sf --max-time 2 "${KC_URL}/realms/master" >/dev/null 2>&1 \
    || curl -sf --max-time 2 "${KC_URL}/realms/${REALM:-am-realm}" >/dev/null 2>&1 \
    || curl -s --max-time 2 -o /dev/null -w "%{http_code}" "${KC_URL}/" | grep -Eq '200|302|303'; then
    ok=1
    break
  fi
  sleep 1
done
if [[ "$ok" != "1" ]]; then
  echo "keycloak not ready at ${KC_URL}" >&2
  tail -20 /tmp/kc-pf-scopes.log >&2 || true
  exit 1
fi
echo "keycloak ready at ${KC_URL}"

cp "$CREDS" /tmp/kc-admin.bak
python3 - <<PY
from pathlib import Path
p = Path("${CREDS}")
kc_url = "${KC_URL}"
lines = []
for line in p.read_text(encoding="utf-8-sig").splitlines():
    if line.startswith("KEYCLOAK_URL="):
        lines.append(f"KEYCLOAK_URL={kc_url}")
    else:
        lines.append(line)
p.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"patched KEYCLOAK_URL -> {kc_url}")
PY

set +e
python3 "$SCRIPT" --env "$ENV"
RC=$?
set -e
cp /tmp/kc-admin.bak "$CREDS"
echo "restored ${CREDS}"
exit "$RC"
