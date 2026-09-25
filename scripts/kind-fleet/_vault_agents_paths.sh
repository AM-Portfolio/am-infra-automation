#!/bin/bash
set -euo pipefail
TOK=$(python3 -c 'import json; d=json.load(open("/data/am-state/vault-prod-infra.json")); print(d.get("root_token") or d.get("token") or "")')
for p in prod/services/am-mcp-gateway prod/services/am-agents-mcp-gateway prod/services/am-agents prod/services/am-tool-agent; do
  echo "=== $p ==="
  code=$(curl -sk -o /tmp/v.json -w "%{http_code}" -H "X-Vault-Token: $TOK" "https://vault.asrax.in/v1/apps/data/$p")
  echo "http=$code"
  python3 -c '
import json
d=json.load(open("/tmp/v.json"))
data=(d.get("data") or {}).get("data")
if not data:
  print("missing", d.get("errors"))
else:
  print("keys", sorted(data.keys()))
  for k in ("LITELLM_MASTER_KEY","LANGFUSE_PUBLIC_KEY","LANGFUSE_SECRET_KEY","AM_MCP_CLIENT_SECRET"):
    print(" ", k, "OK" if data.get(k) is not None else "MISS")
'
done
