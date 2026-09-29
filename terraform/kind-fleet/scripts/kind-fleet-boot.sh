#!/usr/bin/env bash
# Ordered Kind VPS boot: wait nodes → exposer → bridges → hostAliases → smoke.
#
# Usage:
#   ENV=prod ./kind-fleet-boot.sh
#   ./kind-fleet-boot.sh prod
set -euo pipefail

ENV_NAME="${1:-${ENV:-prod}}"
case "$ENV_NAME" in
  preprod|prod|dr) ;;
  *) echo "ENV must be preprod|prod|dr (got: $ENV_NAME)" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")" && pwd)"
export ENV="$ENV_NAME"
export ASRAX_HOME="${ASRAX_HOME:-${HOME:-/root}/.asrax}"
EXPOSER_NAME="${EXPOSER_NAME:-am-port-exposer}"

echo "== kind-fleet-boot ENV=$ENV_NAME =="

echo "== 1 ensure-port-exposer =="
bash "$ROOT/ensure-port-exposer.sh" "$ENV_NAME"

echo "== 2 refresh-cross-cluster-bridges =="
if [[ -x "$ROOT/refresh-cross-cluster-bridges.sh" ]]; then
  bash "$ROOT/refresh-cross-cluster-bridges.sh" "$ENV_NAME" || echo "WARN: bridges refresh failed (continue)"
else
  echo "WARN: missing refresh-cross-cluster-bridges.sh"
fi

echo "== 3 refresh-exposer-hostaliases =="
if [[ -x "$ROOT/refresh-exposer-hostaliases.sh" ]]; then
  ENV="$ENV_NAME" bash "$ROOT/refresh-exposer-hostaliases.sh" || echo "WARN: hostAliases refresh failed (continue)"
else
  echo "WARN: missing refresh-exposer-hostaliases.sh"
fi

echo "== 4 smoke =="
EX_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$EXPOSER_NAME" 2>/dev/null || true)
if [[ -z "$EX_IP" ]]; then
  echo "ERROR: no exposer IP" >&2
  exit 1
fi
tcp_fail=0
soft_fail=0
for p in 6379 27017 5432 9092 7233; do
  if timeout 2 bash -c "echo >/dev/tcp/${EX_IP}/${p}" 2>/dev/null; then
    echo "OPEN $p"
  else
    echo "CLOSED $p"
    tcp_fail=1
  fi
done

# Apps Ready (best-effort — kubeconfig rewrite like hostaliases script)
APPS_CP="am-${ENV_NAME}-apps-control-plane"
SRC="$ASRAX_HOME/kubeconfig.am-${ENV_NAME}-apps.yaml"
OUT="/tmp/kubeconfig.am-${ENV_NAME}-boot.yaml"
if [[ -f "$SRC" ]] && docker inspect "$APPS_CP" >/dev/null 2>&1; then
  CP_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$APPS_CP" | awk '{print $1}')
  python3 - "$SRC" "$CP_IP" "$OUT" <<'PY' || true
import re, socket, sys
src, ip, dst = sys.argv[1], sys.argv[2], sys.argv[3]
t = open(src).read()
for port in (6443, 6444):
    try:
        s = socket.create_connection((ip, port), 2); s.close()
        open(dst, "w").write(re.sub(r"(https?://)[^\s]+", f"https://{ip}:{port}", t, count=1))
        break
    except OSError:
        pass
PY
  if [[ -f "$OUT" ]]; then
    NS_APPS="am-apps-${ENV_NAME}"
    NS_AGENTS="am-agents-${ENV_NAME}"
    # naming: prod uses am-apps-prod / am-market-data-prod
    for dep in am-market-data-${ENV_NAME} am-gateway-${ENV_NAME}; do
      ready=$(kubectl --kubeconfig "$OUT" -n "$NS_APPS" get deploy "$dep" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
      echo "deploy $NS_APPS/$dep ready=${ready:-0}"
    done
    ready=$(kubectl --kubeconfig "$OUT" -n "$NS_AGENTS" get deploy am-support-agent-worker -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    echo "deploy $NS_AGENTS/am-support-agent-worker ready=${ready:-0}"
  fi
fi

# Market HTTP smoke (prod public URL; others best-effort)
MARKET_URL="${MARKET_BATCH_URL:-}"
if [[ -z "$MARKET_URL" ]]; then
  case "$ENV_NAME" in
    prod) MARKET_URL="https://am.asrax.in/market/v1/indices/batch" ;;
    dr) MARKET_URL="https://am-dr.asrax.in/market/v1/indices/batch" ;;
    preprod) MARKET_URL="https://am-preprod.asrax.in/market/v1/indices/batch" ;;
  esac
fi
if [[ -n "$MARKET_URL" ]]; then
  code=$(curl -sS -o /tmp/mb-boot.json -w "%{http_code}" -X POST "$MARKET_URL" \
    -H 'Content-Type: application/json' -d '["NIFTY 50"]' --max-time 20 || echo 000)
  head -c 120 /tmp/mb-boot.json 2>/dev/null; echo
  # 200/4xx JSON OK; 405 + HTML is SPA (market-data down). Public URL may be unreachable from VPS — warn only.
  if [[ "$code" == "000" ]]; then
    echo "WARN: market curl failed/timeout HTTP=$code (public URL may not reach from this VPS)"
    soft_fail=1
  elif [[ "$code" == "405" ]] || grep -qi '<html\|nginx' /tmp/mb-boot.json 2>/dev/null; then
    echo "WARN: market returned SPA/HTML HTTP=$code (market-data not ready yet)"
    soft_fail=1
  else
    echo "market HTTP=$code (JSON path OK)"
  fi
fi

# TCP exposer ports are the hard gate; Ready/curl are soft (timers keep healing).
if [[ "$tcp_fail" -ne 0 ]]; then
  echo "kind-fleet-boot FAILED: exposer TCP ports CLOSED" >&2
  exit 1
fi
if [[ "$soft_fail" -ne 0 ]]; then
  echo "kind-fleet-boot DONE ENV=$ENV_NAME (soft-warn)"
  exit 0
fi
echo "kind-fleet-boot DONE ENV=$ENV_NAME"
