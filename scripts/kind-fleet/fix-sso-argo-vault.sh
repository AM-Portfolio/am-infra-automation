#!/usr/bin/env bash
# Fix SSO: recreate test users, Argo OIDC secret + RBAC, Vault OIDC as default UI method.
set -euo pipefail
ENV="${1:-prod}"
export KCFG="${KUBECONFIG:-/data/am-state/kubeconfig.am-${ENV}-infra.yaml}"
CREDS="/data/am-state/credentials/${ENV}"
export OIDC_FILE="${CREDS}/oidc.env"
SSO="${CREDS}/sso-test-users.env"
KC="${CREDS}/keycloak-admin.env"
VR="${CREDS}/vault-root.env"

NODE_PORT="$(kubectl --kubeconfig "$KCFG" -n identity get svc keycloak -o jsonpath='{.spec.ports[?(@.port==8080)].nodePort}')"
NODE_IP="$(kubectl --kubeconfig "$KCFG" get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
export KC_BASE="http://${NODE_IP}:${NODE_PORT}"
echo "KC_BASE=$KC_BASE env=$ENV"

# Load creds
eval "$(grep -E '^(KEYCLOAK_ADMIN_USER|KEYCLOAK_ADMIN_PASSWORD|KEYCLOAK_REALM)=' "$KC" | sed 's/\r$//' | sed 's/^/export /')"
eval "$(grep -E '^(OIDC_ARGOCD_CLIENT_SECRET|OIDC_VAULT_UI_CLIENT_SECRET)=' "$OIDC_FILE" | sed 's/\r$//' | sed 's/^/export /')"
eval "$(grep -E '^(AM_ADMIN_TEST_USERNAME|AM_ADMIN_TEST_PASSWORD|AM_USER_TEST_USERNAME|AM_USER_TEST_PASSWORD)=' "$SSO" | sed 's/\r$//' | sed 's/^/export /')"

export KC_ADMIN="${KEYCLOAK_ADMIN_USER}"
export KC_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD}"
export REALM="${KEYCLOAK_REALM:-am-realm}"
export ADMIN_USER="${AM_ADMIN_TEST_USERNAME:-am-admin-test}"
export ADMIN_PASS="${AM_ADMIN_TEST_PASSWORD}"
export USER_USER="${AM_USER_TEST_USERNAME:-am-user-test}"
export USER_PASS="${AM_USER_TEST_PASSWORD}"
export ADMIN_ROLES="am-admin,am-ops"
export USER_ROLES="am-user"

python3 <<'PY'
import base64, json, os, subprocess, urllib.error, urllib.parse, urllib.request

def req(method, url, headers=None, data=None, form=None):
    h = dict(headers or {})
    body = data
    if form is not None:
        body = urllib.parse.urlencode(form).encode()
        h["Content-Type"] = "application/x-www-form-urlencoded"
    elif body is not None:
        h.setdefault("Content-Type", "application/json")
    r = urllib.request.Request(url, data=body, headers=h, method=method)
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            raw = resp.read()
            return json.loads(raw.decode()) if raw else None
    except urllib.error.HTTPError as e:
        raise RuntimeError("%s %s -> %s %s" % (method, url, e.code, e.read().decode()[:200]))

base = os.environ["KC_BASE"].rstrip("/")
kcfg = os.environ["KCFG"]
admin, password = os.environ["KC_ADMIN"], os.environ["KC_PASSWORD"]

def token(user, pw):
    return req("POST", f"{base}/realms/master/protocol/openid-connect/token", form={
        "grant_type": "password", "client_id": "admin-cli", "username": user, "password": pw,
    })

try:
    tok = token(admin, password)
except Exception:
    out = subprocess.check_output(["kubectl", "--kubeconfig", kcfg, "-n", "identity", "get", "secret", "keycloak-admin", "-o", "json"], text=True)
    sec = json.loads(out)["data"]
    password = base64.b64decode(sec["password"]).decode()
    admin = "admin"
    for k in ("user", "username", "admin-user"):
        if k in sec:
            admin = base64.b64decode(sec[k]).decode()
            break
    tok = token(admin, password)
    print("using_k8s_keycloak_admin")

h = {"Authorization": f"Bearer {tok['access_token']}", "Content-Type": "application/json"}
realm = os.environ["REALM"]

def ensure_user(username, password, roles):
    found = req("GET", f"{base}/admin/realms/{realm}/users?username={urllib.parse.quote(username)}&exact=true", headers=h) or []
    body_user = {
        "username": username, "enabled": True, "emailVerified": True,
        "email": f"{username}@asrax.in", "firstName": username, "lastName": "test",
        "requiredActions": [],
    }
    if found:
        uid = found[0]["id"]
        req("PUT", f"{base}/admin/realms/{realm}/users/{uid}", headers=h, data=json.dumps(body_user).encode())
    else:
        body_user["credentials"] = [{"type": "password", "value": password, "temporary": False}]
        req("POST", f"{base}/admin/realms/{realm}/users", headers=h, data=json.dumps(body_user).encode())
        found = req("GET", f"{base}/admin/realms/{realm}/users?username={urllib.parse.quote(username)}&exact=true", headers=h) or []
        uid = found[0]["id"]
    req("PUT", f"{base}/admin/realms/{realm}/users/{uid}/reset-password", headers=h,
        data=json.dumps({"type": "password", "value": password, "temporary": False}).encode())
    for role in [r.strip() for r in roles if r.strip()]:
        try:
            role_obj = req("GET", f"{base}/admin/realms/{realm}/roles/{role}", headers=h)
            req("POST", f"{base}/admin/realms/{realm}/users/{uid}/role-mappings/realm", headers=h, data=json.dumps([role_obj]).encode())
        except Exception as e:
            print("role_skip", role, e)
    print(f"user_ok={username}")

ensure_user(os.environ["ADMIN_USER"], os.environ["ADMIN_PASS"], os.environ["ADMIN_ROLES"].split(","))
ensure_user(os.environ["USER_USER"], os.environ["USER_PASS"], os.environ["USER_ROLES"].split(","))

secret = os.environ.get("OIDC_ARGOCD_CLIENT_SECRET", "")
t = req("POST", f"{base}/realms/{realm}/protocol/openid-connect/token", form={
    "grant_type": "password", "client_id": "argocd", "client_secret": secret,
    "username": os.environ["ADMIN_USER"], "password": os.environ["ADMIN_PASS"],
    "scope": "openid profile email groups roles",
})
def pl(jwt):
    p = jwt.split(".")[1]
    p += "=" * (-len(p) % 4)
    return json.loads(base64.urlsafe_b64decode(p.encode()))
at, it = pl(t["access_token"]), pl(t.get("id_token") or t["access_token"])
print("login_ok id.groups=", it.get("groups"), "id.roles=", it.get("roles"), "access.groups=", at.get("groups"))
PY

echo "=== Argo OIDC secret + RBAC (email + groups) ==="
ARGO_SECRET="${OIDC_ARGOCD_CLIENT_SECRET:?missing OIDC_ARGOCD_CLIENT_SECRET}"
B64="$(printf '%s' "$ARGO_SECRET" | base64 -w0 2>/dev/null || printf '%s' "$ARGO_SECRET" | base64)"
kubectl --kubeconfig "$KCFG" -n argocd patch secret argocd-secret --type merge \
  -p "{\"data\":{\"oidc.argocd.clientSecret\":\"${B64}\"}}"

# Map both groups claim and email so admin-test works even if groups mapper lags
kubectl --kubeconfig "$KCFG" -n argocd patch cm argocd-cm --type merge -p "$(python3 - <<'PY'
import json
oidc = '''name: Keycloak
issuer: https://auth.asrax.in/realms/am-realm
clientID: argocd
clientSecret: $oidc.argocd.clientSecret
requestedScopes: ["openid", "profile", "email", "groups", "roles"]
'''
print(json.dumps({"data": {"oidc.config": oidc, "url": "https://argocd.asrax.in"}}))
PY
)"

kubectl --kubeconfig "$KCFG" -n argocd patch cm argocd-rbac-cm --type merge -p "$(python3 - <<'PY'
import json
csv = """g, am-admin, role:admin
g, am-ops, role:admin
g, am-viewer, role:readonly
g, am-user, role:readonly
g, am-admin-test, role:admin
g, am-admin-test@asrax.in, role:admin
"""
print(json.dumps({"data": {"policy.csv": csv, "policy.default": "role:readonly", "scopes": "[groups, email]"}}))
PY
)"

kubectl --kubeconfig "$KCFG" -n argocd rollout restart deploy/argocd-server || true
echo "argo_apps:"
kubectl --kubeconfig "$KCFG" -n argocd get applications.argoproj.io --no-headers 2>/dev/null | wc -l || echo 0
kubectl --kubeconfig "$KCFG" -n argocd get applications.argoproj.io -o name 2>/dev/null | head -20 || true
kubectl --kubeconfig "$KCFG" -n argocd get appprojects -o name 2>/dev/null || true

echo "=== Vault OIDC (default UI method) ==="
if [[ ! -f "$VR" ]]; then
  echo "WARN missing $VR"
  exit 0
fi
eval "$(grep -E '^(VAULT_ADDR|VAULT_TOKEN)=' "$VR" | sed 's/\r$//' | sed 's/^/export /')"
: "${VAULT_TOKEN:?missing VAULT_TOKEN}"
VAULT_SECRET="$(grep '^OIDC_VAULT_UI_CLIENT_SECRET=' "$OIDC_FILE" | cut -d= -f2- || true)"
if [[ -z "$VAULT_SECRET" ]]; then
  echo "WARN no OIDC_VAULT_UI_CLIENT_SECRET — skip vault oidc"
  exit 0
fi
export VAULT_SECRET
VNP="$(kubectl --kubeconfig "$KCFG" -n vault get svc vault -o jsonpath='{.spec.ports[?(@.port==8200)].nodePort}' 2>/dev/null || true)"
if [[ -n "$VNP" ]]; then
  export ADDR_USE="http://${NODE_IP}:${VNP}"
else
  export ADDR_USE="${VAULT_ADDR:-https://vault.asrax.in}"
fi
export ISSUER="https://auth.asrax.in/realms/am-realm"
export REDIR="https://vault.asrax.in/ui/vault/auth/oidc/oidc/callback"
[[ "$ENV" == "dr" ]] && export ISSUER="https://auth-dr.asrax.in/realms/am-realm" && export REDIR="https://vault-dr.asrax.in/ui/vault/auth/oidc/oidc/callback"
echo "vault_addr=$ADDR_USE"

python3 <<'PY'
import json, os, urllib.error, urllib.request

addr = os.environ["ADDR_USE"].rstrip("/")
token = os.environ["VAULT_TOKEN"]
secret = os.environ["VAULT_SECRET"]
issuer = os.environ["ISSUER"]
redir = os.environ["REDIR"]

def vault(method, path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        f"{addr}/v1/{path}",
        data=data,
        method=method,
        headers={"X-Vault-Token": token, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return json.loads(raw.decode()) if raw else {}
    except urllib.error.HTTPError as e:
        err = e.read().decode()[:300]
        if e.code == 400 and "path is already in use" in err:
            return {}
        raise RuntimeError(f"{method} {path} -> {e.code} {err}")

# health
vault("GET", "sys/health")
print("vault_health_ok")

auth = vault("GET", "sys/auth")
if "oidc/" not in auth:
    vault("POST", "sys/auth/oidc", {"type": "oidc", "description": "Keycloak am-realm"})
    print("vault_oidc_enabled")
else:
    print("vault_oidc_already_enabled")

vault("POST", "auth/oidc/config", {
    "oidc_discovery_url": issuer,
    "oidc_client_id": "vault-ui",
    "oidc_client_secret": secret,
    "default_role": "am-admin",
})
print("vault_oidc_config_ok")

for name, policy in [
    ("am-sso-admin", 'path "*" {\n  capabilities = ["create","read","update","delete","list","sudo"]\n}\n'),
    ("am-sso-ops", 'path "apps/data/*" {\n  capabilities = ["read","list"]\n}\npath "sys/policies/*" {\n  capabilities = ["read","list"]\n}\n'),
    ("am-sso-viewer", 'path "apps/data/*" {\n  capabilities = ["read","list"]\n}\n'),
]:
    vault("PUT", f"sys/policies/acl/{name}", {"policy": policy})

for role, pol in [("am-admin", "am-sso-admin"), ("am-ops", "am-sso-ops"), ("am-viewer", "am-sso-viewer")]:
    vault("POST", f"auth/oidc/role/{role}", {
        "role_type": "oidc",
        "user_claim": "email",
        "groups_claim": "groups",
        "bound_audiences": ["vault-ui"],
        "allowed_redirect_uris": [redir, "http://localhost:8200/ui/vault/auth/oidc/oidc/callback"],
        "oidc_scopes": ["openid", "profile", "email", "roles", "groups"],
        "token_policies": [pol],
        "ttl": "24h",
    })
    print(f"vault_role_ok={role}")

vault("POST", "sys/auth/oidc/tune", {"listing_visibility": "unauth"})
print("vault_oidc_tune_ok listing_visibility=unauth default_role=am-admin")
print("Open", redir.replace("/ui/vault/auth/oidc/oidc/callback", "/ui/vault/auth?with=oidc"))
PY

echo "DONE"
echo "Argo: https://argocd.asrax.in → LOG IN VIA KEYCLOAK → am-admin-test"
echo "Vault: https://vault.asrax.in/ui/vault/auth?with=oidc"
