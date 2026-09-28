#!/usr/bin/env bash
set -euo pipefail
set -a
# shellcheck disable=SC1091
source /data/am-state/credentials/dr-infra-stores.env
set +a
export PATH=/usr/local/libexec/am-real:/usr/local/bin:$PATH
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml

echo "=== growthbook backend logs ==="
kubectl logs -n growthbook deploy/growthbook-backend --tail=80 2>&1 | tail -80

echo "=== n8n schema privileges ==="
docker run --rm --network kind -e PGPASSWORD="$POSTGRES_PASSWORD" postgres:16-alpine \
  psql -h postgres-dr.asrax.in -U postgres -d platform -v ON_ERROR_STOP=1 -c "
SELECT has_database_privilege('n8n', 'platform', 'CREATE') AS n8n_create,
       has_database_privilege('n8n', 'platform', 'CONNECT') AS n8n_connect;
SELECT nspname, pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname='n8n';
"

echo "=== mongo DNS + auth ==="
docker exec am-dr-platform-control-plane getent ahostsv4 mongodb-dr.asrax.in || true
docker exec am-dr-platform-control-plane bash -c 'timeout 3 bash -c "</dev/tcp/mongodb-dr.asrax.in/27017" && echo mongo_tcp_ok || echo mongo_tcp_fail'

# Test growthbook mongo user
docker run --rm --network kind mongo:7 \
  mongosh "mongodb://growthbook:${MONGO_USER_GROWTHBOOK}@mongodb-dr.asrax.in:27017/platform?authSource=admin" \
  --eval 'db.runCommand({ ping: 1 })' 2>&1 | tail -20 || true

docker run --rm --network kind mongo:7 \
  mongosh "mongodb://admin:${MONGO_PASSWORD}@mongodb-dr.asrax.in:27017/admin?authSource=admin" \
  --eval 'db.getSiblingDB("platform").getUsers(); db.getUsers()' 2>&1 | tail -40 || true
