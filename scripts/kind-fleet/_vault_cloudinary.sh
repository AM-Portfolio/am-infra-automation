#!/bin/bash
set -euo pipefail
TOK=$(python3 -c 'import json; d=json.load(open("/data/am-state/vault-prod-infra.json")); print(d.get("root_token") or d.get("token") or "")')
curl -sk -H "X-Vault-Token: $TOK" "https://vault.asrax.in/v1/apps/data/prod/services/am-cloudinary-manager" | python3 <<'PY'
import json,sys
d=(json.load(sys.stdin).get("data") or {}).get("data") or {}
print("keys", sorted(d))
for k in ("CLOUDINARY_CLOUD_NAME","CLOUDINARY_API_KEY","CLOUDINARY_API_SECRET","AM_CLOUDINARY_CLIENT_ID","AM_CLOUDINARY_CLIENT_SECRET"):
    v=d.get(k)
    if v is None:
        print(k, "MISSING")
    else:
        print(k, "set", "len="+str(len(str(v))))
PY
