#!/bin/bash
set -euo pipefail
TOK=$(python3 -c 'import json; d=json.load(open("/data/am-state/vault-prod-infra.json")); print(d.get("root_token") or d.get("token") or "")')
export VAULT_ADDR=https://vault.asrax.in VAULT_TOKEN="$TOK" VAULT_SKIP_VERIFY=1
# vault CLI may be missing — use curl
auth_hdr=(-H "X-Vault-Token: $TOK")
list() {
  local p="$1"
  echo "=== LIST $p ==="
  curl -sk "${auth_hdr[@]}" "$VAULT_ADDR/v1/apps/metadata/$p?list=true" | python3 -m json.tool 2>/dev/null | head -60
}
list "prod"
list "prod/shared"
list "prod/services"
echo "=== GET identity google keys ==="
curl -sk "${auth_hdr[@]}" "$VAULT_ADDR/v1/apps/data/prod/services/am-identity" | python3 -c '
import json,sys
d=json.load(sys.stdin).get("data",{}).get("data",{}) or {}
print([k for k in sorted(d) if "GOOGLE" in k.upper() or "GMAIL" in k.upper()])
'
echo "=== GET shared/google ==="
curl -sk "${auth_hdr[@]}" "$VAULT_ADDR/v1/apps/data/prod/shared/google" | python3 -m json.tool 2>/dev/null | head -30
echo "=== GET doc-intelligence keys sample ==="
curl -sk "${auth_hdr[@]}" "$VAULT_ADDR/v1/apps/data/prod/services/am-doc-intelligence" | python3 -c '
import json,sys
d=json.load(sys.stdin).get("data",{}).get("data",{}) or {}
print("keys", sorted(d)[:40])
print("has GOOGLE", [k for k in d if "GOOGLE" in k.upper()])
'
