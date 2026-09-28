#!/usr/bin/env bash
# Switch am-preprod.asrax.in origin via Workers KV (Worker am-nonprod-origin).
# Team SoT: GitHub Actions nonprod-origin.yml (envs nonprod-vps / nonprod-local).
# Break-glass: CLOUDFLARE_API_TOKEN=… ./scripts/kind-fleet/nonprod-origin.sh vps|local [--dry-run]
#
# Required env:
#   CLOUDFLARE_API_TOKEN
# Optional (defaults match am-gitops/cloudflare/wrangler.toml + Asrax CF account):
#   CF_ACCOUNT_ID
#   CF_KV_NAMESPACE_ID   # ORIGIN_KV for am-nonprod-origin
#   NONPROD_ORIGIN_KEY   # default nonprod/origin
set -euo pipefail

ORIGIN="${1:-}"
DRY_RUN=0
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=1

if [[ "$ORIGIN" != "vps" && "$ORIGIN" != "local" ]]; then
  echo "usage: $0 vps|local [--dry-run]" >&2
  exit 1
fi

: "${CLOUDFLARE_API_TOKEN:?set CLOUDFLARE_API_TOKEN}"

# Asrax CF account + ORIGIN_KV id from am-gitops/cloudflare/wrangler.toml
CF_ACCOUNT_ID="${CF_ACCOUNT_ID:-23061f216225f4e2921ba51c2801874d}"
CF_KV_NAMESPACE_ID="${CF_KV_NAMESPACE_ID:-008e8686e3c04a0198ee6236ff865384}"
FLAG_KEY="${NONPROD_ORIGIN_KEY:-nonprod/origin}"
# Cloudflare KV path needs the key URL-encoded (/ → %2F)
FLAG_KEY_ENC="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$FLAG_KEY")"

api() {
  local method="$1" path="$2"
  shift 2
  curl -sS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    "$@"
}

KV_BASE="/accounts/${CF_ACCOUNT_ID}/storage/kv/namespaces/${CF_KV_NAMESPACE_ID}/values/${FLAG_KEY_ENC}"

current="$(api GET "${KV_BASE}" -H "Content-Type: text/plain" || true)"
current="$(printf '%s' "$current" | tr -d '\r\n')"
# GET returns raw value on success, or JSON error body
if echo "$current" | python3 -c 'import sys,json; d=json.load(sys.stdin); sys.exit(0 if isinstance(d, dict) and ("errors" in d or "success" in d) else 1)' 2>/dev/null; then
  echo "WARN: could not read current KV value: $current" >&2
  current="(unread)"
fi

echo "account=${CF_ACCOUNT_ID} kv=${CF_KV_NAMESPACE_ID} key=${FLAG_KEY} current=${current} target=${ORIGIN} dry_run=${DRY_RUN}"

if [[ "$current" == "$ORIGIN" ]]; then
  echo "OK ${FLAG_KEY} already ${ORIGIN}"
  exit 0
fi

echo "SET ${FLAG_KEY}: ${current} -> ${ORIGIN}"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "dry-run complete"
  exit 0
fi

# PUT body is plain text; response is CF JSON {success:true}
put_body="$(curl -sS -X PUT \
  "https://api.cloudflare.com/client/v4${KV_BASE}" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: text/plain" \
  --data-binary "${ORIGIN}")"
printf '%s' "$put_body" | python3 -c 'import sys,json; d=json.load(sys.stdin); assert d.get("success"), d'
echo "patched ${FLAG_KEY}=${ORIGIN}"

verify="$(api GET "${KV_BASE}" -H "Content-Type: text/plain" || true)"
verify="$(printf '%s' "$verify" | tr -d '\r\n')"
if [[ "$verify" != "$ORIGIN" ]]; then
  echo "WARN: put ok but verify got '${verify}' (expected ${ORIGIN})" >&2
fi

echo "smoke…"
code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 20 --max-time 30 \
  -H "Accept: text/html" "https://am-preprod.asrax.in/" || echo fail)"
echo "${code} https://am-preprod.asrax.in/ (x-am-nonprod-origin may be local|vps after Worker)"

echo "nonprod-origin=${ORIGIN} done"
