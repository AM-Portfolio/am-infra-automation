#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:$PATH
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml

echo "=== temporal schema init logs ==="
kubectl logs -n temporal temporal-schema-1-ntg5m -c setup-default-store --tail=80 2>&1 || true
kubectl logs -n temporal temporal-schema-1-ntg5m -c setup-visibility-store --tail=40 2>&1 || true
kubectl logs -n temporal temporal-schema-1-ntg5m --all-containers --tail=40 2>&1 || true

echo "=== temporal env (host/user/db) ==="
kubectl get deploy -n temporal temporal-frontend -o yaml 2>/dev/null | grep -iE 'SQL_|POSTGRES|host|user|database|DBNAME' | head -40 || true
kubectl get secret -n temporal -o name 2>/dev/null
for s in $(kubectl get secret -n temporal -o name 2>/dev/null); do
  echo "-- $s keys --"
  kubectl get -n temporal "$s" -o jsonpath='{.data}' 2>/dev/null | python3 -c 'import sys,json,base64; d=json.load(sys.stdin); print({k:(base64.b64decode(v).decode() if k!="password" else "***") for k,v in d.items()})' 2>/dev/null || true
done

echo "=== openproject earlier error ==="
kubectl logs -n openproject deploy/openproject --tail=200 2>&1 | grep -iE 'error|ERROR|PG::|fatal|permission|denied|Extension|exception' | head -40

echo "=== openproject env host ==="
kubectl set env deployment/openproject -n openproject --list 2>&1 | grep -iE 'DATABASE|POSTGRES|DB_|HOST' | head -20 || true

# Test DB from credentials file
set -a
# shellcheck disable=SC1091
source /data/am-state/credentials/dr-infra-stores.env
set +a
echo "=== psql as temporal ==="
docker run --rm --network kind postgres:16-alpine psql "postgresql://temporal:${PG_USER_TEMPORAL}@postgres-dr.asrax.in:5432/temporal" -c '\conninfo' -c '\l temporal*' 2>&1 | head -30 || true
echo "=== psql as openproject ==="
docker run --rm --network kind postgres:16-alpine psql "postgresql://openproject:${PG_USER_OPENPROJECT}@postgres-dr.asrax.in:5432/openproject" -c '\conninfo' -c 'SELECT current_user, current_database();' 2>&1 | head -30 || true
echo "=== can create extension? ==="
docker run --rm --network kind postgres:16-alpine psql "postgresql://openproject:${PG_USER_OPENPROJECT}@postgres-dr.asrax.in:5432/openproject" -c 'CREATE EXTENSION IF NOT EXISTS btree_gist;' 2>&1 | head -20 || true
echo "=== temporal db exists / schema ==="
docker run --rm --network kind postgres:16-alpine psql "postgresql://temporal:${PG_USER_TEMPORAL}@postgres-dr.asrax.in:5432/postgres" -c '\l' 2>&1 | head -40 || true
