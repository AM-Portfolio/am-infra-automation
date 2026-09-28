#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-infra.yaml

echo "=== MinIO OPENID env ==="
kubectl -n infra get sts minio -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' \
  | grep -E 'MINIO_IDENTITY_OPENID|MINIO_BROWSER' \
  | sed 's/CLIENT_SECRET=.*/CLIENT_SECRET=***/'

echo "=== MinIO logs (openid) ==="
kubectl -n infra logs sts/minio --tail=80 2>/dev/null | grep -iE 'openid|oidc|identity' | tail -20 || true

echo "=== Vault OIDC roles ==="
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-prod-infra-control-plane)
VNP=$(kubectl -n vault get svc vault -o jsonpath='{.spec.ports[?(@.port==8200)].nodePort}')
# shellcheck disable=SC1091
source /data/am-state/credentials/prod/vault-root.env
curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "http://${IP}:${VNP}/v1/auth/oidc/role?list=true" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin).get("data",{}); print(d.get("keys"))'
curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "http://${IP}:${VNP}/v1/auth/oidc/role/am-admin" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin).get("data",{}); print({k:d.get(k) for k in ("bound_audiences","user_claim","groups_claim","allowed_redirect_uris","token_policies","oidc_scopes")})'

echo "=== lago oauth2 logs ==="
kubectl -n billing logs deploy/oauth2-proxy-lago --tail=15 || true

echo "=== final probes ==="
for u in \
  "https://vault.asrax.in/ui/vault/auth?with=oidc" \
  "https://minio.asrax.in/" \
  "https://lago.asrax.in/"
do
  code=$(curl -sI -o /tmp/h.txt -w "%{http_code}" --max-time 15 "$u" || echo err)
  loc=$(grep -i '^location:' /tmp/h.txt | head -1 | tr -d '\r')
  echo "$code $u"
  [[ -n "$loc" ]] && echo "  $loc"
done
echo DONE
