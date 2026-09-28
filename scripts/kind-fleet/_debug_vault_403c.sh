#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-infra.yaml
source /data/am-state/credentials/prod/vault-root.env
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-prod-infra-control-plane)
VNP=$(kubectl -n vault get svc vault -o jsonpath='{.spec.ports[?(@.port==8200)].nodePort}')
ADDR="http://${IP}:${VNP}"
BODY='{"role":"am-admin","redirect_uri":"https://vault.asrax.in/ui/vault/auth/oidc/oidc/callback"}'

echo "=== vault IR ==="
kubectl -n vault get ingressroute.traefik.io vault -o yaml

echo "=== vault svcs ==="
kubectl -n vault get svc -o wide

echo "=== public mounts raw ==="
curl -s "https://vault.asrax.in/v1/sys/internal/ui/mounts" | python3 -m json.tool | head -40

echo "=== nodeport mounts auth keys ==="
curl -sf "$ADDR/v1/sys/internal/ui/mounts" | python3 -c 'import json,sys; print(sorted(json.load(sys.stdin).get("data",{}).get("auth",{}).keys()))'

echo "=== public PUT with CF bypass headers? ==="
curl -s -o /tmp/p.json -w "%{http_code}\n" -X PUT -H "Content-Type: application/json" \
  -H "X-Forwarded-Proto: https" -H "X-Forwarded-For: 1.2.3.4" \
  -d "$BODY" "https://vault.asrax.in/v1/auth/oidc/oidc/auth_url"
python3 -m json.tool </tmp/p.json

echo "=== nodeport with Host vault.asrax.in ==="
curl -s -o /tmp/n.json -w "%{http_code}\n" -X PUT -H "Content-Type: application/json" \
  -H "Host: vault.asrax.in" -d "$BODY" "$ADDR/v1/auth/oidc/oidc/auth_url"
python3 -c 'import json; d=json.load(open("/tmp/n.json")); print(d.get("errors") or "ok")'

echo "=== check default policy / root ==="
curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "$ADDR/v1/sys/auth/oidc/tune" | python3 -m json.tool | head -30

# Any IP capabilities / CIDR on oidc?
curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "$ADDR/v1/auth/oidc/config" | python3 -m json.tool | head -40

echo "=== traefik middlewares on vault IR ==="
kubectl -n vault get ingressroute.traefik.io vault -o jsonpath='{.spec.routes[*].middlewares}' ; echo
kubectl -n infra get middleware 2>/dev/null | head -20
