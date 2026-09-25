#!/bin/bash
set -euo pipefail
TOK=$(python3 -c 'import json; d=json.load(open("/data/am-state/vault-prod-infra.json")); print(d.get("root_token") or d.get("token") or "")')
export VAULT_ADDR=https://vault.asrax.in
auth=(-H "X-Vault-Token: $TOK")
for p in prod/services/am-email-extractor prod/services/am-document-processor prod/services/am-identity prod/infra/shared-api; do
  echo "=== $p ==="
  curl -sk "${auth[@]}" "$VAULT_ADDR/v1/apps/data/$p" | python3 -c '
import json,sys
body=json.load(sys.stdin)
d=(body.get("data") or {}).get("data")
if d is None:
  print("MISSING", body.get("errors"))
else:
  print("keys", sorted(d.keys()))
  for k in ("GOOGLE_CLIENT_ID","GOOGLE_CLIENT_SECRET","AM_DOC_INTELLIGENCE_CLIENT_ID","AM_DOC_INTELLIGENCE_CLIENT_SECRET"):
    v=d.get(k)
    if v is not None:
      print(f"  {k}=set len={len(str(v))}")
'
done
