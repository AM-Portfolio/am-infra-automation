#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-infra.yaml
echo "=== oauth2-proxy-lago ==="
kubectl -n billing get pods -l app=oauth2-proxy-lago -o wide
kubectl -n billing logs deploy/oauth2-proxy-lago --tail=40 || true
echo "=== minio ==="
kubectl -n infra get pods | grep -i minio || true
kubectl -n infra get sts minio -o yaml | grep -E 'MINIO_IDENTITY_OPENID|MINIO_BROWSER' | sed 's/CLIENT_SECRET:.*/CLIENT_SECRET: ***/' || true
echo "=== probes ==="
for u in \
  "https://vault.asrax.in/ui/vault/auth?with=oidc" \
  "https://minio-console.asrax.in/" \
  "https://minio.asrax.in/" \
  "https://lago.asrax.in/"
do
  echo "== $u"
  curl -sI --max-time 20 "$u" | head -12 || echo fail
done
# Keycloak clients redirect check via admin PF
echo "=== ensure Keycloak redirect URIs ==="
NODE_PORT=$(kubectl -n identity get svc keycloak -o jsonpath='{.spec.ports[?(@.port==8080)].nodePort}')
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
KC=http://${NODE_IP}:${NODE_PORT}
PW=$(kubectl -n identity get secret keycloak-admin -o jsonpath='{.data.password}' | base64 -d)
TOK=$(curl -sf -X POST "$KC/realms/master/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=admin-cli&username=admin&password=$PW" | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')
AUTH="Authorization: Bearer $TOK"
for CID in minio lago vault-ui; do
  RAW=$(curl -sf -H "$AUTH" "$KC/admin/realms/am-realm/clients?clientId=$CID")
  UUID=$(echo "$RAW" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["id"] if d else "")')
  [[ -z "$UUID" ]] && { echo "missing client $CID"; continue; }
  BODY=$(curl -sf -H "$AUTH" "$KC/admin/realms/am-realm/clients/$UUID")
  python3 - <<PY
import json, os, urllib.request
cid = "$CID"
uuid = "$UUID"
kc = "$KC"
tok = "$TOK"
body = json.loads('''$BODY'''.replace("'", "\\'") if False else open("/dev/stdin").read())
PY
done
# simpler update redirects
python3 <<PY
import json, urllib.request, urllib.parse, os

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
      "https://minio-console.asrax.in/*",
      "https://minio-console.asrax.in/oauth_callback",
      "https://minio.asrax.in/oauth_callback",
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
    print("redirects_ok", cid, patch["redirectUris"])
PY
