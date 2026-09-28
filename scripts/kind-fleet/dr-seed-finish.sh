#!/usr/bin/env bash
set -euo pipefail
SEED=/data/am-state/seed/disaster-latest
set -a; # shellcheck disable=SC1091
source /data/am-state/credentials/dr-infra-stores.env
set +a
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-infra.yaml
export PATH=/usr/local/libexec/am-real:/usr/local/bin:$PATH
export PGPASSWORD="$POSTGRES_PASSWORD"

echo "=== keycloak users ==="
docker run --rm -i --network host -e PGPASSWORD postgres:16-alpine \
  psql -h 127.0.0.1 -U postgres -d keycloak -Atc 'SELECT count(*) FROM user_entity;'

echo "=== finish redis seed ==="
kubectl -n infra scale statefulset/redis-master --replicas=0
for i in $(seq 1 40); do
  kubectl -n infra get pod redis-master-0 >/dev/null 2>&1 || break
  sleep 2
done
docker exec am-dr-infra-control-plane mkdir -p /var/am-infra/data/redis
docker cp "$SEED/redis/kind/data/dump.rdb" am-dr-infra-control-plane:/var/am-infra/data/redis/dump.rdb
docker exec am-dr-infra-control-plane chown 999:999 /var/am-infra/data/redis/dump.rdb || true
docker exec am-dr-infra-control-plane ls -la /var/am-infra/data/redis/
kubectl -n infra scale statefulset/redis-master --replicas=1
kubectl -n infra rollout status statefulset/redis-master --timeout=180s
docker run --rm --network host redis:7.2-alpine \
  redis-cli -h 127.0.0.1 -a "$REDIS_PASSWORD" PING
docker run --rm --network host redis:7.2-alpine \
  redis-cli -h 127.0.0.1 -a "$REDIS_PASSWORD" DBSIZE

echo "=== mongo db names ==="
docker run --rm --network host mongo:7 \
  mongosh --quiet "mongodb://admin:${MONGO_PASSWORD}@127.0.0.1:27017/admin" \
  --eval 'db.adminCommand({listDatabases:1}).databases.map(function(d){return d.name}).join(",")'

echo "=== pods ==="
kubectl -n infra get pods
