#!/bin/bash
set -euo pipefail
TOK=$(python3 -c 'import json; d=json.load(open("/data/am-state/vault-prod-infra.json")); print(d.get("root_token") or d.get("token") or "")')
for p in prod/services/am-mkt-agents prod/services/am-identity; do
  echo "=== $p ==="
  code=$(curl -sk -o /tmp/v.json -w "%{http_code}" -H "X-Vault-Token: $TOK" "https://vault.asrax.in/v1/apps/data/$p")
  echo "http=$code"
  python3 -c 'import json; d=json.load(open("/tmp/v.json")); data=(d.get("data") or {}).get("data"); print("keys", sorted(data.keys()) if data else d.get("errors"))'
done
# fetch remote mkt vault-mappings
echo "=== live mkt SPC if any ==="
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
kubectl -n am-agents-prod get secretproviderclass am-mkt-agents-prod-vault-secrets -o jsonpath='{.spec.parameters.objects}' 2>/dev/null | head -c 2000 || echo none
echo
