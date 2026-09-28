#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-infra.yaml
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-prod-infra-control-plane)
VNP=$(kubectl -n vault get svc vault -o jsonpath='{.spec.ports[?(@.port==8200)].nodePort}')
source /data/am-state/credentials/prod/vault-root.env
ADDR="http://${IP}:${VNP}"

echo "=== unauth ui mounts ==="
curl -sf "$ADDR/v1/sys/internal/ui/mounts" | python3 -c '
import json,sys
d=json.load(sys.stdin).get("data",{}).get("auth",{})
for k,v in d.items():
  if "oidc" in k or v.get("type")=="oidc":
    print(k, {x:v.get(x) for x in ("type","description","options")})
'
echo "=== tune ==="
curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "$ADDR/v1/sys/auth/oidc/tune" | python3 -m json.tool || true

echo "=== auth_url empty role (no token) ==="
curl -s -o /tmp/au.json -w "%{http_code}" -X PUT -H "Content-Type: application/json" \
  -d '{"role":"","redirect_uri":"https://vault.asrax.in/ui/vault/auth/oidc/oidc/callback"}' \
  "$ADDR/v1/auth/oidc/oidc/auth_url"
echo
python3 -m json.tool </tmp/au.json || cat /tmp/au.json

echo "=== auth_url role=am-admin ==="
curl -s -o /tmp/au2.json -w "%{http_code}" -X PUT -H "Content-Type: application/json" \
  -d '{"role":"am-admin","redirect_uri":"https://vault.asrax.in/ui/vault/auth/oidc/oidc/callback"}' \
  "$ADDR/v1/auth/oidc/oidc/auth_url"
echo
python3 -m json.tool </tmp/au2.json || cat /tmp/au2.json

echo "=== auth_url no role key ==="
curl -s -o /tmp/au3.json -w "%{http_code}" -X PUT -H "Content-Type: application/json" \
  -d '{"redirect_uri":"https://vault.asrax.in/ui/vault/auth/oidc/oidc/callback"}' \
  "$ADDR/v1/auth/oidc/oidc/auth_url"
echo
python3 -m json.tool </tmp/au3.json || cat /tmp/au3.json
