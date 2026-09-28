#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-infra.yaml
source /data/am-state/credentials/prod/vault-root.env
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-prod-infra-control-plane)
VNP=$(kubectl -n vault get svc vault -o jsonpath='{.spec.ports[?(@.port==8200)].nodePort}')
ADDR="http://${IP}:${VNP}"

echo "=== vault version ==="
curl -sf "$ADDR/v1/sys/health" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("version"), d.get("cluster_name"))'

echo "=== unauth ui mounts ==="
curl -sf "$ADDR/v1/sys/internal/ui/mounts" -o /tmp/uimounts.json
python3 - <<'PY'
import json
d=json.load(open("/tmp/uimounts.json")).get("data",{}).get("auth",{})
for k,v in sorted(d.items()):
    if "oidc" in k.lower() or v.get("type")=="oidc":
        print("path=", k)
        print(" type=", v.get("type"))
        print(" desc=", v.get("description"))
        print(" options=", v.get("options"))
        print(" keys=", sorted(v.keys()))
print("all_auth_paths=", sorted(d.keys()))
PY

echo "=== roles ==="
curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "$ADDR/v1/auth/oidc/role?list=true" -o /tmp/roles.json
python3 -c 'import json; print(json.load(open("/tmp/roles.json")).get("data"))'
curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "$ADDR/v1/auth/oidc/role/am-admin" -o /tmp/role.json
python3 -c 'import json; d=json.load(open("/tmp/role.json")).get("data",{}); print({k:d.get(k) for k in ("role_type","bound_audiences","bound_claims","allowed_redirect_uris","token_policies")})'

echo "=== public auth_url ==="
for role in am-admin "" default; do
  code=$(curl -s -o /tmp/au.json -w "%{http_code}" -X PUT -H "Content-Type: application/json" \
    --data-binary "{\"role\":\"$role\",\"redirect_uri\":\"https://vault.asrax.in/ui/vault/auth/oidc/oidc/callback\"}" \
    "https://vault.asrax.in/v1/auth/oidc/oidc/auth_url")
  python3 -c "import json; d=json.load(open('/tmp/au.json')); print('role=[$role]', $code, d.get('errors') or (d.get('data') or {}).get('auth_url','')[:90])"
done

echo "=== config ==="
curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "$ADDR/v1/auth/oidc/config" -o /tmp/cfg.json
python3 -c 'import json; d=json.load(open("/tmp/cfg.json")).get("data",{}); print({k:d.get(k) for k in ("default_role","oidc_client_id","oidc_discovery_url")})'
