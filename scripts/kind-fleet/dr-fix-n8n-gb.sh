#!/usr/bin/env bash
set -euo pipefail
set -a
# shellcheck disable=SC1091
source /data/am-state/credentials/dr-infra-stores.env
set +a
export PATH=/usr/local/libexec/am-real:/usr/local/bin:$PATH
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml

echo "=== GRANT CREATE on platform for schema apps ==="
docker run --rm --network kind -e PGPASSWORD="$POSTGRES_PASSWORD" postgres:16-alpine \
  psql -h postgres-dr.asrax.in -U postgres -d postgres -v ON_ERROR_STOP=1 -c "
GRANT CREATE ON DATABASE platform TO n8n, openproject, keycloak, litellm, langfuse;
"
docker run --rm --network kind -e PGPASSWORD="$POSTGRES_PASSWORD" postgres:16-alpine \
  psql -h postgres-dr.asrax.in -U postgres -d platform -v ON_ERROR_STOP=1 -c "
GRANT ALL ON SCHEMA n8n TO n8n;
GRANT ALL ON ALL TABLES IN SCHEMA n8n TO n8n;
GRANT ALL ON ALL SEQUENCES IN SCHEMA n8n TO n8n;
ALTER DEFAULT PRIVILEGES IN SCHEMA n8n GRANT ALL ON TABLES TO n8n;
ALTER DEFAULT PRIVILEGES IN SCHEMA n8n GRANT ALL ON SEQUENCES TO n8n;
"

echo "=== recreate growthbook mongo user on admin (authSource=admin) ==="
docker run --rm --network kind mongo:7 \
  mongosh "mongodb://admin:${MONGO_PASSWORD}@mongodb-dr.asrax.in:27017/admin?authSource=admin" --quiet --eval "
const pwd = '${MONGO_USER_GROWTHBOOK}';
const admin = db.getSiblingDB('admin');
const platform = db.getSiblingDB('platform');
try { admin.dropUser('growthbook'); } catch (e) {}
try { platform.dropUser('growthbook'); } catch (e) {}
admin.createUser({
  user: 'growthbook',
  pwd: pwd,
  roles: [ { role: 'readWrite', db: 'platform' } ]
});
print('growthbook user created on admin');
printjson(admin.getUser('growthbook'));
"

echo "=== verify growthbook auth ==="
docker run --rm --network kind mongo:7 \
  mongosh "mongodb://growthbook:${MONGO_USER_GROWTHBOOK}@mongodb-dr.asrax.in:27017/platform?authSource=admin" \
  --quiet --eval 'db.runCommand({ ping: 1 })' 2>&1

echo "=== restart n8n + growthbook ==="
kubectl rollout restart deployment -n n8n
kubectl rollout restart deployment/growthbook-backend -n growthbook

sleep 25
kubectl get pods -n n8n
kubectl get pods -n growthbook
kubectl logs -n n8n -l app.kubernetes.io/name=n8n --tail=20 2>&1 | tail -20 || true
kubectl logs -n growthbook deploy/growthbook-backend --tail=25 2>&1 | tail -25 || true
