#!/usr/bin/env bash
# Critical Contabo DB dump → R2 asrax-disaster (prod/ dated + prod/latest).
# Uploads via Cloudflare R2 HTTP API (Bearer token) — no S3 keys required.
set -euo pipefail

STAMP="${DUMP_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
PREFIX="${DUMP_PREFIX:-prod}"
BUCKET="${R2_BUCKET:-asrax-disaster}"
ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID required}"
# Auth: prefer Global API Key (email+key) for R2 object writes; Bearer token often list-only.
CF_EMAIL="${CLOUDFLARE_EMAIL:-}"
CF_GLOBAL_KEY="${CLOUDFLARE_API_KEY:-${CLOUDFLARE_GLOBAL_API_TOKEN:-}}"
CF_BEARER="${CLOUDFLARE_API_TOKEN:-}"
WORKDIR="${WORKDIR:-/dump}"
BASE_API="https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/r2/buckets/${BUCKET}/objects"

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

# Critical PG DBs for failover allowlist (Keycloak/platform + user + subscription).
PG_DATABASES="${PG_DATABASES:-platform am_subscription user_platform lago}"

mkdir -p "$WORKDIR/postgres" "$WORKDIR/mongodb" "$WORKDIR/redis"
echo "dump_start stamp=$STAMP prefix=$PREFIX bucket=$BUCKET"

upload() {
  local local_path="$1"
  local object_key="$2"
  local ctype="${3:-application/octet-stream}"
  # Keep path separators; encode only unsafe characters (CF API expects / in object key path).
  local encoded
  encoded=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe="/"))' "$object_key")
  echo "upload r2://$BUCKET/$object_key ($(wc -c <"$local_path") bytes)"
  if [ "$AUTH_MODE" = "global" ]; then
    code=$(curl -sS -o /tmp/cf_up.json -w "%{http_code}" -X PUT \
      "${BASE_API}/${encoded}" \
      -H "X-Auth-Email: ${CF_EMAIL}" \
      -H "X-Auth-Key: ${CF_GLOBAL_KEY}" \
      -H "Content-Type: ${ctype}" \
      --data-binary @"${local_path}")
  else
    code=$(curl -sS -o /tmp/cf_up.json -w "%{http_code}" -X PUT \
      "${BASE_API}/${encoded}" \
      -H "Authorization: Bearer ${CF_BEARER}" \
      -H "Content-Type: ${ctype}" \
      --data-binary @"${local_path}")
  fi
  if [ "$code" != "200" ] && [ "$code" != "201" ]; then
    echo "upload_fail http=$code key=$object_key body=$(head -c 400 /tmp/cf_up.json || true)" >&2
    exit 1
  fi
}

# --- PostgreSQL ---
for db in $PG_DATABASES; do
  out="$WORKDIR/postgres/${db}.sql.gz"
  echo "pg_dump db=$db"
  pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$db" \
    --no-owner --no-acl --format=plain \
    | gzip -c >"$out"
  upload "$out" "${PREFIX}/${STAMP}/postgres/${db}.sql.gz" "application/gzip"
  upload "$out" "${PREFIX}/latest/postgres/${db}.sql.gz" "application/gzip"
done

# --- MongoDB full instance (gzip archive) ---
MONGO_URI="mongodb://${MONGO_USER}:${MONGO_PASSWORD}@${MONGO_HOST}:${MONGO_PORT}/?authSource=admin"
mout="$WORKDIR/mongodb/full-instance.archive.gz"
echo "mongodump full-instance"
mongodump --uri="$MONGO_URI" --archive="$mout" --gzip
upload "$mout" "${PREFIX}/${STAMP}/mongodb/full-instance.archive.gz" "application/gzip"
upload "$mout" "${PREFIX}/latest/mongodb/full-instance.archive.gz" "application/gzip"

# --- Redis RDB ---
rout="$WORKDIR/redis/dump.rdb"
echo "redis BGSAVE + GET"
if [ -n "$REDIS_PASSWORD" ]; then
  redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --no-auth-warning BGSAVE >/dev/null
  # wait briefly for background save
  for _ in $(seq 1 30); do
    st=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --no-auth-warning LASTSAVE)
    sleep 1
    st2=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --no-auth-warning LASTSAVE)
    [ "$st2" != "$st" ] && break
  done
  redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --no-auth-warning --rdb "$rout"
else
  redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --rdb "$rout"
fi
gzip -c "$rout" >"${rout}.gz"
upload "${rout}.gz" "${PREFIX}/${STAMP}/redis/dump.rdb.gz" "application/gzip"
upload "${rout}.gz" "${PREFIX}/latest/redis/dump.rdb.gz" "application/gzip"

# --- Markers ---
ok="$WORKDIR/BACKUP_OK.txt"
printf 'ok stamp=%s host=%s\n' "$STAMP" "$(hostname)" >"$ok"
upload "$ok" "${PREFIX}/${STAMP}/BACKUP_OK.txt" "text/plain"
upload "$ok" "${PREFIX}/latest/BACKUP_OK.txt" "text/plain"

manifest="$WORKDIR/MANIFEST.json"
cat >"$manifest" <<EOF
{"stamp":"$STAMP","prefix":"$PREFIX","bucket":"$BUCKET","postgres":$(printf '%s\n' $PG_DATABASES | python3 -c 'import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))'),"mongodb":"full-instance","redis":"dump.rdb.gz"}
EOF
upload "$manifest" "${PREFIX}/${STAMP}/MANIFEST.json" "application/json"
upload "$manifest" "${PREFIX}/latest/MANIFEST.json" "application/json"

echo "dump_complete stamp=$STAMP"
