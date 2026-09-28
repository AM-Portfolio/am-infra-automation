#!/usr/bin/env bash
# Switch bare asrax.in HTTPS CNAMEs between Contabo (prod tunnel) and DR tunnel.
# Until CF Load Balancing is subscribed this is the edge-primary actuator.
# Usage: edge-primary.sh prod|dr [--dry-run]
set -euo pipefail

PRIMARY="${1:-}"
DRY_RUN=0
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=1

if [[ "$PRIMARY" != "prod" && "$PRIMARY" != "dr" ]]; then
  echo "usage: $0 prod|dr [--dry-run]" >&2
  exit 1
fi

: "${CLOUDFLARE_API_TOKEN:?set CLOUDFLARE_API_TOKEN}"
ZONE_NAME="${CLOUDFLARE_ZONE_NAME:-asrax.in}"
PROD_TUNNEL="${PROD_TUNNEL_ID:-68770b3c-a4a1-43ee-9c53-adaf47760132}.cfargotunnel.com"
DR_TUNNEL="${DR_TUNNEL_ID:-64cd1dd4-ccd1-4c41-8233-d0525c3f05cf}.cfargotunnel.com"

if [[ "$PRIMARY" == "prod" ]]; then
  TARGET="$PROD_TUNNEL"
else
  TARGET="$DR_TUNNEL"
fi

HOSTS=(
  am auth vault argocd minio s3 influx traefik pgadmin mongo-express
  kafka-ui redis-ui temporal lago n8n growthbook openproject litellm
  langfuse novu corp asrax
)

api() {
  local method="$1" path="$2"
  shift 2
  curl -sS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "$@"
}

ZONE_ID="$(api GET "/zones?name=${ZONE_NAME}" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["result"][0]["id"])')"
echo "zone=${ZONE_NAME} id=${ZONE_ID} primary=${PRIMARY} target=${TARGET} dry_run=${DRY_RUN}"

patch_host() {
  local name="$1" # bare label or @ for apex
  local fqdn
  if [[ "$name" == "@" ]]; then
    fqdn="$ZONE_NAME"
  else
    fqdn="${name}.${ZONE_NAME}"
  fi
  local list
  list="$(api GET "/zones/${ZONE_ID}/dns_records?name=${fqdn}&type=CNAME")"
  local rid content
  rid="$(echo "$list" | python3 -c 'import sys,json; r=json.load(sys.stdin).get("result") or []; print(r[0]["id"] if r else "")')"
  content="$(echo "$list" | python3 -c 'import sys,json; r=json.load(sys.stdin).get("result") or []; print(r[0]["content"] if r else "")')"
  if [[ -z "$rid" ]]; then
    echo "MISSING ${fqdn}"
    return 0
  fi
  if [[ "$content" == "$TARGET" ]]; then
    echo "OK ${fqdn} already ${TARGET}"
    return 0
  fi
  echo "SET ${fqdn}: ${content} -> ${TARGET}"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  api PATCH "/zones/${ZONE_ID}/dns_records/${rid}" \
    --data "{\"content\":\"${TARGET}\",\"proxied\":true}" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); assert d.get("success"), d; print("patched", d["result"]["name"])'
}

for h in "${HOSTS[@]}"; do
  patch_host "$h"
done
patch_host "@"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "dry-run complete"
  exit 0
fi

echo "smoke…"
for u in \
  "https://am.${ZONE_NAME}/health" \
  "https://auth.${ZONE_NAME}/realms/master" \
  "https://vault.${ZONE_NAME}/v1/sys/health"
do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 20 --max-time 30 "$u" || echo fail)"
  echo "${code} ${u}"
done

echo "edge-primary=${PRIMARY} done"
