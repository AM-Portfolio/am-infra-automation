#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-infra.yaml
source /data/am-state/credentials/prod/vault-root.env
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-prod-infra-control-plane)
VNP=$(kubectl -n vault get svc vault -o jsonpath='{.spec.ports[?(@.port==8200)].nodePort}')
ADDR="http://${IP}:${VNP}"
BODY='{"role":"am-admin","redirect_uri":"https://vault.asrax.in/ui/vault/auth/oidc/oidc/callback"}'

echo "=== nodeport auth_url ==="
curl -s -o /tmp/np.json -w "code=%{http_code}\n" -X PUT -H "Content-Type: application/json" -d "$BODY" \
  "$ADDR/v1/auth/oidc/oidc/auth_url"
python3 -c 'import json; d=json.load(open("/tmp/np.json")); print(d.get("errors") or "ok", (d.get("data") or {}).get("auth_url","")[:100])'

echo "=== public auth_url full headers ==="
curl -sI -X PUT -H "Content-Type: application/json" -d "$BODY" \
  "https://vault.asrax.in/v1/auth/oidc/oidc/auth_url" | head -20
echo "=== public auth_url body ==="
curl -s -o /tmp/pub.json -w "code=%{http_code}\n" -X PUT -H "Content-Type: application/json" -d "$BODY" \
  "https://vault.asrax.in/v1/auth/oidc/oidc/auth_url"
python3 -c 'import json; print(json.load(open("/tmp/pub.json")))'

echo "=== via traefik in-cluster ==="
# hit vault service through traefik if possible
kubectl -n vault get ingressroute.traefik.io vault -o yaml | head -40

echo "=== vault policy for oidc auth_url (default) ==="
# unauthenticated should be allowed for auth_url - check if deny exists
curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "$ADDR/v1/sys/policies/acl?list=true" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("data",{}).get("keys"))' || true

echo "=== test from vault pod localhost ==="
kubectl -n vault exec vault-0 -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 wget -qO- --method=PUT --header="Content-Type: application/json" --body-data='"'"'"$BODY"'"'"' http://127.0.0.1:8200/v1/auth/oidc/oidc/auth_url' 2>&1 | head -5 || \
kubectl -n vault exec vault-0 -- wget -qO- --post-data="$BODY" --header='Content-Type: application/json' \
  http://127.0.0.1:8200/v1/auth/oidc/oidc/auth_url 2>&1 | head -20 || true
