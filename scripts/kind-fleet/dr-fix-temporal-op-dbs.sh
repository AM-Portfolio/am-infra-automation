#!/usr/bin/env bash
set -euo pipefail
set -a
# shellcheck disable=SC1091
source /data/am-state/credentials/dr-infra-stores.env
set +a
export PATH=/usr/local/libexec/am-real:/usr/local/bin:$PATH
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml

run_psql() {
  local db="$1"; shift
  docker run --rm --network kind -e PGPASSWORD="$POSTGRES_PASSWORD" \
    postgres:16-alpine psql -h postgres-dr.asrax.in -U postgres -d "$db" -v ON_ERROR_STOP=1 "$@"
}

echo "=== create temporal + temporal_visibility DBs ==="
run_psql postgres -tc "SELECT 1 FROM pg_database WHERE datname='temporal'" | grep -q 1 || \
  run_psql postgres -c "CREATE DATABASE temporal OWNER temporal"
run_psql postgres -tc "SELECT 1 FROM pg_database WHERE datname='temporal_visibility'" | grep -q 1 || \
  run_psql postgres -c "CREATE DATABASE temporal_visibility OWNER temporal"

run_psql temporal -c "ALTER DATABASE temporal OWNER TO temporal; GRANT ALL ON SCHEMA public TO temporal; CREATE EXTENSION IF NOT EXISTS btree_gin; CREATE EXTENSION IF NOT EXISTS btree_gist;"
run_psql temporal_visibility -c "ALTER DATABASE temporal_visibility OWNER TO temporal; GRANT ALL ON SCHEMA public TO temporal; CREATE EXTENSION IF NOT EXISTS btree_gin; CREATE EXTENSION IF NOT EXISTS btree_gist;"

echo "=== openproject extensions on platform ==="
run_psql platform -c "CREATE EXTENSION IF NOT EXISTS btree_gist; CREATE EXTENSION IF NOT EXISTS pg_trgm;"
run_psql postgres -c "GRANT CREATE ON DATABASE platform TO openproject;"

echo "=== verify DBs ==="
run_psql postgres -c '\l temporal*'

echo "=== restart workloads ==="
kubectl get jobs -n temporal -o name 2>/dev/null | xargs -r -n1 kubectl delete -n temporal --wait=false || true
kubectl delete pods -n temporal --all --wait=false || true
kubectl rollout restart deployment/openproject -n openproject || true

sleep 25
echo "=== status ==="
kubectl get pods -n temporal
kubectl get pods -n openproject
