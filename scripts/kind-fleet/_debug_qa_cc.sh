#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
POD=$(kubectl -n am-agents-prod get pods -l app.kubernetes.io/instance=am-qa-agents-prod -o jsonpath='{.items[0].metadata.name}')
echo "POD=$POD"
kubectl -n am-agents-prod describe pod "$POD" 2>&1 | grep -A6 FailedMount | tail -30
echo "=== SPC ==="
kubectl -n am-agents-prod get secretproviderclass am-qa-agents-prod-vault-secrets -o jsonpath='{.spec.parameters.objects}' | python3 -c '
import sys,yaml
for o in (yaml.safe_load(sys.stdin.read()) or []):
  print(o.get("objectName"), "->", o.get("secretPath"), "key=", o.get("secretKey"))
'
TOK=$(python3 -c 'import json; d=json.load(open("/data/am-state/vault-prod-infra.json")); print(d.get("root_token") or d.get("token") or "")')
for p in prod/runtime/modules/qa prod/services/am-qa-agents prod/services/am-identity; do
  echo "=== vault $p ==="
  curl -sk -o /tmp/v.json -w "http=%{http_code}\n" -H "X-Vault-Token: $TOK" "https://vault.asrax.in/v1/apps/data/$p"
  python3 -c 'import json; d=json.load(open("/tmp/v.json")); data=(d.get("data") or {}).get("data"); print("keys", sorted(data.keys()) if data else d.get("errors"))'
done
echo "=== identity AM_MCP keys ==="
curl -sk -H "X-Vault-Token: $TOK" "https://vault.asrax.in/v1/apps/data/prod/services/am-identity" | python3 -c '
import json,sys
d=(json.load(sys.stdin).get("data") or {}).get("data") or {}
for k in ("AM_MCP_CLIENT_ID","AM_MCP_CLIENT_SECRET"):
  print(k, "OK" if d.get(k) is not None else "MISS")
'
echo "=== support worker ==="
kubectl -n am-agents-prod logs am-support-agent-worker-5946644568-dng8c --tail=20 2>&1 || true
