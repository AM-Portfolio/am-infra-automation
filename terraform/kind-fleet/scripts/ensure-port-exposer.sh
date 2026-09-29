#!/usr/bin/env bash
# Ensure am-port-exposer is up with store + Temporal gRPC socat mappings.
# Recreates the container if Kind nodes are missing targets or any mapped port is CLOSED.
#
# Usage:
#   ENV=prod ./ensure-port-exposer.sh
#   ./ensure-port-exposer.sh prod
set -euo pipefail

ENV_NAME="${1:-${ENV:-prod}}"
case "$ENV_NAME" in
  preprod|prod|dr) ;;
  *) echo "ENV must be preprod|prod|dr (got: $ENV_NAME)" >&2; exit 1 ;;
esac

EXPOSER_NAME="${EXPOSER_NAME:-am-port-exposer}"
DOMAIN="${DOMAIN:-asrax.in}"
TEMPORAL_HOST_PORT=7233
TEMPORAL_NODE_PORT=30723
WAIT_SECS="${WAIT_SECS:-600}"

# Store NodePorts (infra Kind)
declare -a PORT_MAP=(
  "5432:30432"
  "27017:30017"
  "6379:30379"
  "9092:30092"
  "8086:30806"
  "9000:30900"
  "8200:30820"
)

# Prefer worker for stores on prod (mongo NodePort on CP flaky); DR uses infra CP.
INFRA_CP="am-${ENV_NAME}-infra-control-plane"
INFRA_W="am-${ENV_NAME}-infra-worker"
APPS_CP="am-${ENV_NAME}-apps-control-plane"

if [[ "$ENV_NAME" == "prod" ]]; then
  STORE_NODE="$INFRA_W"
  # fall back to CP if worker missing
  docker inspect "$STORE_NODE" >/dev/null 2>&1 || STORE_NODE="$INFRA_CP"
  TEMPORAL_NODE="$INFRA_CP"
  RPC_ALIAS="temporal-rpc-prod.${DOMAIN}"
  ALIASES=(
    "postgres.${DOMAIN}" "mongo.${DOMAIN}" "mongodb.${DOMAIN}"
    "redis.${DOMAIN}" "kafka.${DOMAIN}" "minio.${DOMAIN}"
    "$RPC_ALIAS"
  )
elif [[ "$ENV_NAME" == "dr" ]]; then
  STORE_NODE="$INFRA_CP"
  docker inspect "$INFRA_W" >/dev/null 2>&1 && STORE_NODE="$INFRA_W"
  TEMPORAL_NODE="$INFRA_CP"
  RPC_ALIAS="temporal-rpc-dr.${DOMAIN}"
  ALIASES=(
    "postgres-dr.${DOMAIN}" "mongo-dr.${DOMAIN}" "mongodb-dr.${DOMAIN}"
    "redis-dr.${DOMAIN}" "kafka-dr.${DOMAIN}" "minio-dr.${DOMAIN}"
    "influxdb-dr.${DOMAIN}"
    "$RPC_ALIAS"
  )
else
  # preprod Kind Contabo (if present)
  STORE_NODE="$INFRA_W"
  docker inspect "$STORE_NODE" >/dev/null 2>&1 || STORE_NODE="$INFRA_CP"
  TEMPORAL_NODE="$INFRA_CP"
  RPC_ALIAS="temporal-rpc-preprod.${DOMAIN}"
  ALIASES=(
    "postgres.${DOMAIN}" "mongo.${DOMAIN}" "mongodb.${DOMAIN}"
    "redis.${DOMAIN}" "kafka.${DOMAIN}" "minio.${DOMAIN}"
    "$RPC_ALIAS"
  )
fi

wait_nodes() {
  local deadline=$((SECONDS + WAIT_SECS))
  echo "wait Kind nodes STORE=$STORE_NODE TEMPORAL=$TEMPORAL_NODE APPS=$APPS_CP (upto ${WAIT_SECS}s)"
  while (( SECONDS < deadline )); do
    local ok=1
    docker inspect "$STORE_NODE" >/dev/null 2>&1 || ok=0
    docker inspect "$TEMPORAL_NODE" >/dev/null 2>&1 || ok=0
    docker inspect "$APPS_CP" >/dev/null 2>&1 || ok=0
    if [[ "$ok" -eq 1 ]]; then
      echo "kind nodes present"
      return 0
    fi
    sleep 5
  done
  echo "ERROR: Kind nodes not ready within ${WAIT_SECS}s" >&2
  return 1
}

port_open() {
  local ip="$1" port="$2"
  timeout 2 bash -c "echo >/dev/tcp/${ip}/${port}" 2>/dev/null
}

exposer_healthy() {
  local ip
  ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$EXPOSER_NAME" 2>/dev/null || true)
  [[ -n "$ip" ]] || return 1
  local p
  for p in 6379 27017 5432 9092 "$TEMPORAL_HOST_PORT"; do
    port_open "$ip" "$p" || return 1
  done
  return 0
}

recreate_exposer() {
  local inner="" alias_args=() p host np
  for p in "${PORT_MAP[@]}"; do
    host="${p%%:*}"
    np="${p##*:}"
    inner+="socat TCP4-LISTEN:${host},fork,reuseaddr TCP4:${STORE_NODE}:${np} & "
  done
  inner+="socat TCP4-LISTEN:${TEMPORAL_HOST_PORT},fork,reuseaddr TCP4:${TEMPORAL_NODE}:${TEMPORAL_NODE_PORT} & wait"

  local a
  for a in "${ALIASES[@]}"; do
    alias_args+=(--network-alias "$a")
  done

  echo "recreate $EXPOSER_NAME store=$STORE_NODE temporal=$TEMPORAL_NODE:${TEMPORAL_NODE_PORT}"
  docker rm -f "$EXPOSER_NAME" 2>/dev/null || true
  docker run -d --name "$EXPOSER_NAME" \
    -p 5432:5432 -p 27017:27017 -p 6379:6379 -p 9092:9092 \
    -p 8086:8086 -p 9000:9000 -p 8200:8200 -p "${TEMPORAL_HOST_PORT}:${TEMPORAL_HOST_PORT}" \
    --network kind "${alias_args[@]}" --restart always \
    --entrypoint /bin/sh alpine/socat -c "$inner"
  sleep 3
  test "$(docker inspect -f '{{.State.Running}}' "$EXPOSER_NAME")" = "true"
  local ip
  ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$EXPOSER_NAME")
  echo "EXPOSER_IP=$ip aliases=${ALIASES[*]}"
}

wait_nodes

if docker inspect "$EXPOSER_NAME" >/dev/null 2>&1 && exposer_healthy; then
  echo "exposer healthy — leave running"
  docker inspect -f 'EXPOSER_IP={{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$EXPOSER_NAME"
  exit 0
fi

recreate_exposer
if ! exposer_healthy; then
  echo "ERROR: exposer ports still closed after recreate" >&2
  exit 1
fi
echo "exposer OK"
