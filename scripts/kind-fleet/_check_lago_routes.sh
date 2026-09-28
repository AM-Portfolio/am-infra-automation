#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-infra.yaml

echo "=== ingressroutes traefik.io ==="
kubectl get ingressroute.traefik.io -A

echo "=== lago IR ==="
kubectl -n billing get ingressroute.traefik.io lago -o yaml || true
echo "=== lago-oidc IR ==="
kubectl -n billing get ingressroute.traefik.io lago-oidc -o yaml || true
echo "=== minio-console IR ==="
kubectl -n infra get ingressroute.traefik.io minio-console -o yaml || true

echo "=== traefik svc ==="
kubectl -n infra get svc traefik -o wide || true

echo "=== patch lago IR to oauth2-proxy ==="
# Prefer patching the existing lago route so Host(lago.asrax.in) hits oauth2-proxy
if kubectl -n billing get ingressroute.traefik.io lago >/dev/null 2>&1; then
  kubectl -n billing patch ingressroute.traefik.io lago --type=json -p='[
    {"op":"replace","path":"/spec/routes/0/services","value":[{"name":"oauth2-proxy-lago","port":4180}]}
  ]' && echo "patched lago -> oauth2-proxy-lago:4180" || echo "patch failed"
fi

# Also ensure lago-oidc exists with higher priority
cat >/tmp/lago-oidc-ir.yaml <<'EOF'
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: lago-oidc
  namespace: billing
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`lago.asrax.in`)
      kind: Rule
      priority: 100
      services:
        - name: oauth2-proxy-lago
          port: 4180
EOF
kubectl apply -f /tmp/lago-oidc-ir.yaml

# Point NodePort front door at oauth2-proxy as well (CF may hit NodePort 30830)
echo "=== retarget lago-front-nodeport selector ==="
kubectl -n billing get svc lago-front-nodeport -o yaml | head -40
# Create NodePort on oauth2-proxy using same 30830 if possible, or patch selector
# Safer: change lago-front-nodeport to select oauth2 and map port 80->4180
kubectl -n billing patch svc lago-front-nodeport --type=json -p='[
  {"op":"replace","path":"/spec/selector","value":{"app":"oauth2-proxy-lago"}},
  {"op":"replace","path":"/spec/ports","value":[{"name":"http","port":80,"targetPort":4180,"nodePort":30830,"protocol":"TCP"}]}
]' && echo "nodeport -> oauth2-proxy-lago" || echo "nodeport patch failed"

# MinIO: use minio.asrax.in as browser redirect (prod host)
echo "=== fix minio OPENID redirect to minio.asrax.in ==="
DISC=https://auth.asrax.in/realms/am-realm/.well-known/openid-configuration
if kubectl -n infra get sts minio >/dev/null 2>&1; then
  kubectl -n infra set env sts/minio \
    MINIO_IDENTITY_OPENID_REDIRECT_URI=https://minio.asrax.in/oauth_callback \
    MINIO_BROWSER_REDIRECT_URL=https://minio.asrax.in \
    MINIO_IDENTITY_OPENID_CONFIG_URL="$DISC" \
    || true
  kubectl -n infra rollout status sts/minio --timeout=180s || true
fi

echo "=== Keycloak redirect URIs ==="
NODE_PORT=$(kubectl -n identity get svc keycloak -o jsonpath='{.spec.ports[?(@.port==8080)].nodePort}')
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
KC=http://${NODE_IP}:${NODE_PORT}
PW=$(kubectl -n identity get secret keycloak-admin -o jsonpath='{.data.password}' | base64 -d)
TOK=$(curl -sf -X POST "$KC/realms/master/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=admin-cli&username=admin&password=$PW" \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')

python3 <<PY
import json, urllib.request, urllib.parse
kc = "$KC"
tok = "$TOK"
h = {"Authorization": f"Bearer {tok}", "Content-Type": "application/json"}

def req(method, url, data=None):
    r = urllib.request.Request(url, data=data, headers=h, method=method)
    with urllib.request.urlopen(r, timeout=30) as resp:
        raw = resp.read()
        return json.loads(raw.decode()) if raw else None

updates = {
  "minio": {
    "redirectUris": [
      "https://minio.asrax.in/*",
      "https://minio.asrax.in/oauth_callback",
      "https://minio-console.asrax.in/*",
      "https://minio-console.asrax.in/oauth_callback",
    ],
    "webOrigins": ["https://minio.asrax.in", "https://minio-console.asrax.in"],
  },
  "lago": {
    "redirectUris": ["https://lago.asrax.in/*", "https://lago.asrax.in/oauth2/callback"],
    "webOrigins": ["https://lago.asrax.in"],
  },
  "vault-ui": {
    "redirectUris": [
      "https://vault.asrax.in/ui/vault/auth/oidc/oidc/callback",
      "http://localhost:8200/ui/vault/auth/oidc/oidc/callback",
    ],
    "webOrigins": ["https://vault.asrax.in"],
  },
}
for cid, patch in updates.items():
    found = req("GET", f"{kc}/admin/realms/am-realm/clients?clientId={urllib.parse.quote(cid)}") or []
    if not found:
        print("missing", cid)
        continue
    body = req("GET", f"{kc}/admin/realms/am-realm/clients/{found[0]['id']}")
    body["redirectUris"] = patch["redirectUris"]
    body["webOrigins"] = patch["webOrigins"]
    req("PUT", f"{kc}/admin/realms/am-realm/clients/{found[0]['id']}", json.dumps(body).encode())
    print("redirects_ok", cid)

# print vault oidc status
print("clients_ok")
PY

echo "=== Vault OIDC auth methods ==="
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-prod-infra-control-plane)
VNP=$(kubectl -n vault get svc vault -o jsonpath='{.spec.ports[?(@.port==8200)].nodePort}')
# shellcheck disable=SC1091
source /data/am-state/credentials/prod/vault-root.env
curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "http://${IP}:${VNP}/v1/sys/auth" \
  | python3 -c 'import json,sys; print(sorted(k for k in json.load(sys.stdin) if k.endswith("/")))'
curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "http://${IP}:${VNP}/v1/auth/oidc/config" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin).get("data",{}); print("vault_oidc", d.get("oidc_client_id"), d.get("default_role"), d.get("oidc_discovery_url"))'

echo "=== HTTP probes ==="
for u in \
  "https://vault.asrax.in/ui/vault/auth?with=oidc" \
  "https://minio.asrax.in/" \
  "https://lago.asrax.in/"
do
  echo "== $u"
  curl -sI --max-time 20 "$u" | head -15 || echo fail
done

echo "=== lago IR after ==="
kubectl -n billing get ingressroute.traefik.io lago lago-oidc -o wide || true
kubectl -n billing get svc lago-front-nodeport oauth2-proxy-lago -o wide
echo DONE
