#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
POD=$(kubectl -n am-agents-prod get pods -l app.kubernetes.io/instance=am-qa-agents-prod -o jsonpath='{.items[0].metadata.name}')
echo "POD=$POD STATUS=$(kubectl -n am-agents-prod get pod $POD -o jsonpath='{.status.phase}')"
kubectl -n am-agents-prod describe pod "$POD" | tail -25
echo "=== SPC objects ==="
kubectl -n am-agents-prod get secretproviderclass am-qa-agents-prod-vault-secrets -o jsonpath='{.spec.parameters.objects}'
echo
TOK=$(python3 -c 'import json; d=json.load(open("/data/am-state/vault-prod-infra.json")); print(d.get("root_token") or d.get("token") or "")')
echo "=== vault runtime/modules/qa ==="
curl -sk -w "\nhttp=%{http_code}\n" -H "X-Vault-Token: $TOK" "https://vault.asrax.in/v1/apps/data/prod/runtime/modules/qa" | head -40
echo "=== list runtime ==="
curl -sk -H "X-Vault-Token: $TOK" "https://vault.asrax.in/v1/apps/metadata/prod/runtime?list=true" | head -40
echo "=== identity mcp ==="
curl -sk -H "X-Vault-Token: $TOK" "https://vault.asrax.in/v1/apps/data/prod/services/am-identity" | python3 -c 'import json,sys; d=(json.load(sys.stdin).get("data") or {}).get("data") or {}; print({k: (k in d) for k in ["AM_MCP_CLIENT_ID","AM_MCP_CLIENT_SECRET"]})'
