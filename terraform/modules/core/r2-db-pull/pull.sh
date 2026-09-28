#!/usr/bin/env bash
# DR slave: pull prod/latest from R2 asrax-disaster → restore PG + Mongo on local infra.
# Redis RDB apply is logged but skipped (needs redis process restart / PVC) — FLUSHALL optional.
set -euo pipefail

PREFIX="${DUMP_PREFIX:-prod}"
SOURCE_PREFIX="${SOURCE_PREFIX:-${PREFIX}/latest}"
BUCKET="${R2_BUCKET:-asrax-disaster}"
ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID required}"
CF_EMAIL="${CLOUDFLARE_EMAIL:-}"
CF_GLOBAL_KEY="${CLOUDFLARE_API_KEY:-${CLOUDFLARE_GLOBAL_API_TOKEN:-}}"
CF_BEARER="${CLOUDFLARE_API_TOKEN:-}"
WORKDIR="${WORKDIR:-/restore}"
BASE_API="https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/r2/buckets/${BUCKET}/objects"
FLUSH_REDIS="${FLUSH_REDIS:-false}"

if [ -n "$CF_EMAIL" ] && [ -n "$CF_GLOBAL_KEY" ]; then
  AUTH_MODE=global
elif [ -n "$CF_BEARER" ]; then
  AUTH_MODE=bearer
else
  echo "need CLOUDFLARE_EMAIL+CLOUDFLARE_API_KEY or CLOUDFLARE_API_TOKEN" >&2
  exit 1
fi

PGHOST="${PGHOST:-postgresql.${NAMESPACE:-infra}.svc.cluster.local}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:?PGPASSWORD required}"
export PGPASSWORD

MONGO_HOST="${MONGO_HOST:-mongodb.${NAMESPACE:-infra}.svc.cluster.local}"
MONGO_PORT="${MONGO_PORT:-27017}"
MONGO_USER="${MONGO_USER:-admin}"
MONGO_PASSWORD="${MONGO_PASSWORD:?MONGO_PASSWORD required}"

REDIS_HOST="${REDIS_HOST:-redis-master.${NAMESPACE:-infra}.svc.cluster.local}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

PG_DATABASES="${PG_DATABASES:-platform am_subscription user_platform lago}"

mkdir -p "$WORKDIR/postgres" "$WORKDIR/mongodb" "$WORKDIR/redis"
echo "pull_start source=$SOURCE_PREFIX bucket=$BUCKET"

# download KEY PATH [optional=false] — exit 1 on miss unless optional=true
download() {
  local object_key="$1"
  local local_path="$2"
  local optional="${3:-false}"
  local encoded code
  encoded=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe="/"))' "$object_key")
  echo "download r2://$BUCKET/$object_key -> $local_path"
  if [ "$AUTH_MODE" = "global" ]; then
    code=$(curl -sS -o "$local_path" -w "%{http_code}" -X GET \
      "${BASE_API}/${encoded}" \
      -H "X-Auth-Email: ${CF_EMAIL}" \
      -H "X-Auth-Key: ${CF_GLOBAL_KEY}")
  else
    code=$(curl -sS -o "$local_path" -w "%{http_code}" -X GET \
      "${BASE_API}/${encoded}" \
      -H "Authorization: Bearer ${CF_BEARER}")
  fi
  if [ "$code" != "200" ]; then
    echo "download_fail http=$code key=$object_key body=$(head -c 300 "$local_path" || true)" >&2
    if [ "$optional" = "true" ]; then
      rm -f "$local_path"
      return 1
    fi
    exit 1
  fi
  if head -c 20 "$local_path" | grep -q '"success":false'; then
    echo "download_fail json_error key=$object_key" >&2
    head -c 400 "$local_path" >&2 || true
    if [ "$optional" = "true" ]; then
      rm -f "$local_path"
      return 1
    fi
    exit 1
  fi
  return 0
}

# Marker first (proves SoT freshness)
download "${SOURCE_PREFIX}/BACKUP_OK.txt" "$WORKDIR/BACKUP_OK.txt"
download "${SOURCE_PREFIX}/MANIFEST.json" "$WORKDIR/MANIFEST.json"
echo "source_marker=$(tr '\n' ' ' <"$WORKDIR/BACKUP_OK.txt")"

# --- PostgreSQL restore (destructive on DR slave) ---
# Dump is --no-owner/--no-acl; still tolerate extension/role noise (ON_ERROR_STOP off).
for db in $PG_DATABASES; do
  gz="$WORKDIR/postgres/${db}.sql.gz"
  download "${SOURCE_PREFIX}/postgres/${db}.sql.gz" "$gz"
  echo "pg_restore db=$db bytes=$(wc -c <"$gz")"
  psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -v ON_ERROR_STOP=1 <<SQL
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '${db}' AND pid <> pg_backend_pid();
SQL
  dropdb -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" --if-exists --force "$db" 2>/dev/null \
    || dropdb -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" --if-exists "$db"
  createdb -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" "$db"
  set +e
  gunzip -c "$gz" | psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$db" \
    -v ON_ERROR_STOP=0 --quiet 2>"$WORKDIR/postgres/${db}.psql.err"
  pg_rc=${PIPESTATUS[1]:-1}
  set -e
  err_n=$(wc -l <"$WORKDIR/postgres/${db}.psql.err" || echo 0)
  echo "pg_restore_done db=$db psql_rc=$pg_rc stderr_lines=$err_n"
  if [ "$err_n" -gt 0 ]; then
    echo "pg_restore_stderr_tail db=$db" >&2
    tail -40 "$WORKDIR/postgres/${db}.psql.err" >&2 || true
  fi
  # Must have at least one user table/schema beyond empty DB
  tbl=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$db" -Atc \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema');")
  echo "pg_restore_tables db=$db count=$tbl"
  if [ "${tbl:-0}" -lt 1 ]; then
    echo "pg_restore_empty db=$db" >&2
    exit 1
  fi
done

# --- MongoDB ---
mout="$WORKDIR/mongodb/full-instance.archive.gz"
download "${SOURCE_PREFIX}/mongodb/full-instance.archive.gz" "$mout"
MONGO_URI="mongodb://${MONGO_USER}:${MONGO_PASSWORD}@${MONGO_HOST}:${MONGO_PORT}/?authSource=admin"
echo "mongorestore --drop"
mongorestore --uri="$MONGO_URI" --archive="$mout" --gzip --drop

# --- Redis: download for evidence; RDB reload needs redis pod restart (not done here) ---
if download "${SOURCE_PREFIX}/redis/dump.rdb.gz" "$WORKDIR/redis/dump.rdb.gz" true; then
  echo "redis_rdb_downloaded bytes=$(wc -c <"$WORKDIR/redis/dump.rdb.gz")"
fi
if [ "$FLUSH_REDIS" = "true" ] && [ -n "$REDIS_PASSWORD" ]; then
  echo "redis FLUSHALL (RDB file reload skipped — needs pod restart)"
  redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --no-auth-warning FLUSHALL
fi

echo "pull_complete source=$SOURCE_PREFIX"
