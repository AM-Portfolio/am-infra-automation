#!/usr/bin/env bash
# Restore DR Kind stores from /data/am-state/seed/disaster-latest (Kind packs).
# Run on VPS3 as root. Uses localhost exposer ports (loopback allowed).
set -euo pipefail

SEED="${SEED:-/data/am-state/seed/disaster-latest}"
CREDS="${CREDS:-/data/am-state/credentials/dr-infra-stores.env}"
# shellcheck disable=SC1090
set -a; source "$CREDS"; set +a
export PGPASSWORD="${POSTGRES_PASSWORD:?}"
PGIMAGE="${PGIMAGE:-postgres:16-alpine}"
MONGOIMAGE="${MONGOIMAGE:-mongo:7}"

pg() {
  docker run --rm -i --network host -e PGPASSWORD "$PGIMAGE" \
    psql -h 127.0.0.1 -U "${POSTGRES_USER:-postgres}" "$@"
}

echo "==> Postgres Kind dumps"
for f in "$SEED"/postgres/kind/data/*.sql.gz; do
  [[ -f "$f" ]] || continue
  db="$(basename "$f" .sql.gz)"
  echo "--- $db"
  exists="$(echo "SELECT 1 FROM pg_database WHERE datname='${db}'" | pg -d postgres -At || true)"
  if [[ "$exists" != "1" ]]; then
    echo "CREATE DATABASE ${db};" | pg -d postgres
  fi
  gunzip -c "$f" | pg -d "$db" -v ON_ERROR_STOP=0 >/tmp/restore-"$db".log 2>&1 || true
  echo "    log lines=$(wc -l </tmp/restore-"$db".log)"
done

echo "==> Keycloak user_entity count (if present)"
echo "SELECT count(*) FROM user_entity;" | pg -d keycloak -At 2>/dev/null || echo "(no keycloak.user_entity)"

echo "==> MongoDB prod full-instance archive"
ARCH="$SEED/mongodb/prod/data/full-instance.archive.gz"
if [[ -f "$ARCH" ]]; then
  docker run --rm --network host \
    -v "$SEED/mongodb/prod/data:/in:ro" \
    "$MONGOIMAGE" \
    mongorestore --host=127.0.0.1 --port=27017 \
      -u "${MONGO_USER:-admin}" -p "${MONGO_PASSWORD}" --authenticationDatabase=admin \
      --gzip --archive=/in/full-instance.archive.gz --drop
fi

echo "==> Redis Kind dump.rdb into Kind node hostPath"
RDB="$SEED/redis/kind/data/dump.rdb"
if [[ -f "$RDB" ]]; then
  kubectl -n infra scale statefulset/redis-master --replicas=0
  for i in $(seq 1 40); do
    kubectl -n infra get pod redis-master-0 >/dev/null 2>&1 || break
    sleep 2
  done
  docker exec am-dr-infra-control-plane mkdir -p /var/am-infra/data/redis
  docker cp "$RDB" am-dr-infra-control-plane:/var/am-infra/data/redis/dump.rdb
  docker exec am-dr-infra-control-plane chown 999:999 /var/am-infra/data/redis/dump.rdb || true
  docker exec am-dr-infra-control-plane ls -la /var/am-infra/data/redis/
  kubectl -n infra scale statefulset/redis-master --replicas=1
  kubectl -n infra rollout status statefulset/redis-master --timeout=180s || true
  # ping
  docker run --rm --network host redis:7.2-alpine \
    redis-cli -h 127.0.0.1 -a "${REDIS_PASSWORD}" PING || true
  docker run --rm --network host redis:7.2-alpine \
    redis-cli -h 127.0.0.1 -a "${REDIS_PASSWORD}" DBSIZE || true
fi

echo "==> Seed complete"
echo "SELECT datname FROM pg_database WHERE datistemplate=false ORDER BY 1;" | pg -d postgres
kubectl -n infra get pods | grep -E 'postgres|mongo|redis|minio|NAME' || true
