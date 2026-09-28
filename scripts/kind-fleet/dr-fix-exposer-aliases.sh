#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:$PATH

# Recreate am-port-exposer with *-dr network aliases (split-horizon).
NODE=am-dr-infra-control-plane
ALIASES=(
  --network-alias postgres-dr.asrax.in
  --network-alias mongo-dr.asrax.in
  --network-alias mongodb-dr.asrax.in
  --network-alias redis-dr.asrax.in
  --network-alias kafka-dr.asrax.in
  --network-alias minio-dr.asrax.in
  --network-alias influxdb-dr.asrax.in
)
PORTS="-p 5432:5432 -p 27017:27017 -p 6379:6379 -p 9092:9092 -p 8086:8086 -p 9000:9000 -p 8200:8200"
INNER="socat TCP4-LISTEN:5432,fork,reuseaddr TCP4:${NODE}:30432 & socat TCP4-LISTEN:27017,fork,reuseaddr TCP4:${NODE}:30017 & socat TCP4-LISTEN:6379,fork,reuseaddr TCP4:${NODE}:30379 & socat TCP4-LISTEN:9092,fork,reuseaddr TCP4:${NODE}:30092 & socat TCP4-LISTEN:8086,fork,reuseaddr TCP4:${NODE}:30806 & socat TCP4-LISTEN:9000,fork,reuseaddr TCP4:${NODE}:30900 & socat TCP4-LISTEN:8200,fork,reuseaddr TCP4:${NODE}:30820 & wait"

docker rm -f am-port-exposer 2>/dev/null || true
# shellcheck disable=SC2086
docker run -d --name am-port-exposer $PORTS --network kind "${ALIASES[@]}" --restart always --entrypoint /bin/sh alpine/socat -c "$INNER"
sleep 3
test "$(docker inspect -f '{{.State.Running}}' am-port-exposer)" = "true"
EXPOSER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-port-exposer)
echo "exposer up ip=$EXPOSER_IP"

echo "=== DNS from platform node ==="
docker exec am-dr-platform-control-plane getent hosts postgres-dr.asrax.in
docker exec am-dr-platform-control-plane getent hosts redis-dr.asrax.in
docker exec am-dr-platform-control-plane bash -c "timeout 3 bash -c '</dev/tcp/postgres-dr.asrax.in/5432' && echo pg_ok || echo pg_fail"

# Restart keycloak so it retries DB with fixed DNS
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml
kubectl delete pod -n identity keycloak-0 --wait=false 2>/dev/null || true
echo "keycloak pod delete requested"

# Sync exposer TF state by tainting so next apply matches (optional)
cd /opt/am-infra-automation/terraform/kind-fleet/dr/exposer
# Copy updated main.tf will be scp'd; just record IP
echo "$EXPOSER_IP" > /data/am-state/dr-exposer-ip.txt
