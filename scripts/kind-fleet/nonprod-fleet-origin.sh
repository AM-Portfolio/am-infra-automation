#!/usr/bin/env bash
# Bulk-move nonprod plane hosts between Contabo VPS (preprod tunnel) and laptop (dev tunnel).
# Team SoT: GitHub Actions nonprod-fleet-origin.yml
# Break-glass: CLOUDFLARE_API_TOKEN=… ./scripts/kind-fleet/nonprod-fleet-origin.sh <plane> <origin> [--dry-run]
#
# plane=dev     → PATCH all *-dev.asrax.in / am-dev.asrax.in CNAMEs to target tunnel
# plane=preprod → set Workers KV nonprod/origin (SoT for am-preprod Worker); PATCH other *-preprod
#                 tunnel CNAMEs (never retarget am-preprod.asrax.in itself)
#
# Refuses: bare prod hosts, *-dr.* (owned by edge-primary.sh)
set -euo pipefail

PLANE="${1:-}"
ORIGIN="${2:-}"
DRY_RUN=0
[[ "${3:-}" == "--dry-run" ]] && DRY_RUN=1

if [[ "$PLANE" != "dev" && "$PLANE" != "preprod" ]]; then
  echo "usage: $0 dev|preprod vps|local [--dry-run]" >&2
  exit 1
fi
if [[ "$ORIGIN" != "vps" && "$ORIGIN" != "local" ]]; then
  echo "usage: $0 dev|preprod vps|local [--dry-run]" >&2
  exit 1
fi

: "${CLOUDFLARE_API_TOKEN:?set CLOUDFLARE_API_TOKEN}"

ZONE_NAME="${CLOUDFLARE_ZONE_NAME:-asrax.in}"
# Tunnel UUIDs (same as am-obs-platform cf_edge.TUNNEL_SITE)
PREPROD_TUNNEL_ID="${PREPROD_TUNNEL_ID:-5f1be911-22da-4dc1-ab4c-8194692d73e8}"
DEV_TUNNEL_ID="${DEV_TUNNEL_ID:-d652365f-bdb2-4382-a4e1-28b628bcf5d3}"
VPS_TARGET="${PREPROD_TUNNEL_ID}.cfargotunnel.com"
LOCAL_TARGET="${DEV_TUNNEL_ID}.cfargotunnel.com"

if [[ "$ORIGIN" == "vps" ]]; then
  TARGET="$VPS_TARGET"
else
  TARGET="$LOCAL_TARGET"
fi

CF_ACCOUNT_ID="${CF_ACCOUNT_ID:-23061f216225f4e2921ba51c2801874d}"
CF_KV_NAMESPACE_ID="${CF_KV_NAMESPACE_ID:-008e8686e3c04a0198ee6236ff865384}"
FLAG_KEY="${NONPROD_ORIGIN_KEY:-nonprod/origin}"
FLAG_KEY_ENC="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$FLAG_KEY")"

api() {
  local method="$1" path="$2"
  shift 2
  curl -sS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "$@"
}

ZONE_ID="$(api GET "/zones?name=${ZONE_NAME}" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["result"][0]["id"])')"
echo "zone=${ZONE_NAME} id=${ZONE_ID} plane=${PLANE} origin=${ORIGIN} target=${TARGET} dry_run=${DRY_RUN}"

set_kv_origin() {
  local kv_base="/accounts/${CF_ACCOUNT_ID}/storage/kv/namespaces/${CF_KV_NAMESPACE_ID}/values/${FLAG_KEY_ENC}"
  local current
  current="$(curl -sS -X GET "https://api.cloudflare.com/client/v4${kv_base}" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: text/plain" || true)"
  current="$(printf '%s' "$current" | tr -d '\r\n')"
  if echo "$current" | python3 -c 'import sys,json; d=json.load(sys.stdin); sys.exit(0 if isinstance(d, dict) and ("errors" in d or "success" in d) else 1)' 2>/dev/null; then
    echo "WARN: could not read current KV value: $current" >&2
    current="(unread)"
  fi
  echo "KV key=${FLAG_KEY} current=${current} target=${ORIGIN}"
  if [[ "$current" == "$ORIGIN" ]]; then
    echo "OK ${FLAG_KEY} already ${ORIGIN}"
    return 0
  fi
  echo "SET ${FLAG_KEY}: ${current} -> ${ORIGIN}"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  local put_body
  put_body="$(curl -sS -X PUT "https://api.cloudflare.com/client/v4${kv_base}" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: text/plain" \
    --data-binary "${ORIGIN}")"
  printf '%s' "$put_body" | python3 -c 'import sys,json; d=json.load(sys.stdin); assert d.get("success"), d'
  echo "patched ${FLAG_KEY}=${ORIGIN}"
}

# Returns 0 if fqdn should be patched for this plane
should_patch() {
  local fqdn="$1"
  local lower
  lower="$(printf '%s' "$fqdn" | tr '[:upper:]' '[:lower:]')"
  # Never touch DR drill hosts or apex / bare prod (no -dev/-preprod/-dr suffix)
  if [[ "$lower" == *"-dr.asrax.in" ]] || [[ "$lower" == "asrax.in" ]] || [[ "$lower" == "www.asrax.in" ]]; then
    return 1
  fi
  if [[ "$PLANE" == "dev" ]]; then
    if [[ "$lower" == "am-dev.asrax.in" ]] || [[ "$lower" == *"-dev.asrax.in" ]]; then
      return 0
    fi
    return 1
  fi
  # preprod plane: never retarget Worker host am-preprod.asrax.in
  if [[ "$lower" == "am-preprod.asrax.in" ]]; then
    return 1
  fi
  # leave dig backend alone when flipping preprod (Worker uses am-dev for local)
  if [[ "$lower" == "am-dev.asrax.in" ]] || [[ "$lower" == *"-dev.asrax.in" ]]; then
    return 1
  fi
  if [[ "$lower" == "am-preprod-vps.asrax.in" ]] || [[ "$lower" == *"-preprod.asrax.in" ]]; then
    return 0
  fi
  return 1
}

patch_record() {
  local rid="$1" fqdn="$2" content="$3"
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

# Paginate all CNAMEs and patch matching hosts
page=1
patched=0
skipped=0
while true; do
  page_json="$(api GET "/zones/${ZONE_ID}/dns_records?per_page=100&page=${page}&type=CNAME")"
  mapfile -t lines < <(echo "$page_json" | python3 -c '
import sys, json
d = json.load(sys.stdin)
for r in d.get("result") or []:
    content = r.get("content") or ""
    if "cfargotunnel.com" not in content:
        continue
    rid = r.get("id") or ""
    name = r.get("name") or ""
    print("%s\t%s\t%s" % (rid, name, content))
')
  for line in "${lines[@]:-}"; do
    [[ -z "$line" ]] && continue
    IFS=$'\t' read -r rid fqdn content <<<"$line"
    if should_patch "$fqdn"; then
      patch_record "$rid" "$fqdn" "$content"
      patched=$((patched + 1))
    else
      skipped=$((skipped + 1))
    fi
  done
  total_pages="$(echo "$page_json" | python3 -c 'import sys,json; print((json.load(sys.stdin).get("result_info") or {}).get("total_pages") or 1)')"
  if [[ "$page" -ge "$total_pages" ]]; then
    break
  fi
  page=$((page + 1))
done

echo "cname candidates considered; patched_or_ok=${patched} skipped=${skipped}"

if [[ "$PLANE" == "preprod" ]]; then
  set_kv_origin
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "dry-run complete plane=${PLANE} origin=${ORIGIN}"
  exit 0
fi

echo "smoke…"
if [[ "$PLANE" == "dev" ]]; then
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 20 --max-time 30 \
    "https://am-dev.asrax.in/" || echo fail)"
  echo "${code} https://am-dev.asrax.in/"
else
  hdrs="$(mktemp)"
  code="$(curl -sS -D "$hdrs" -o /dev/null -w "%{http_code}" --connect-timeout 20 --max-time 30 \
    -H "Accept: text/html" "https://am-preprod.asrax.in/" || echo fail)"
  eff="$(grep -i '^x-am-nonprod-origin:' "$hdrs" | awk '{print $2}' | tr -d '\r' || true)"
  rm -f "$hdrs"
  echo "${code} https://am-preprod.asrax.in/ x-am-nonprod-origin=${eff:-"(none)"}"
fi

echo "nonprod-fleet-origin plane=${PLANE} origin=${ORIGIN} done"
