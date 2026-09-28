#!/usr/bin/env python3
"""Password-grant smoke: confirm groups/roles claims for a test user (no secret print)."""
import json
import os
import sys
import urllib.parse
import urllib.request

env = sys.argv[1] if len(sys.argv) > 1 else "prod"
base = os.environ.get("KC_BASE", "http://127.0.0.1:18080")
realm = "am-realm"
cred = f"/data/am-state/credentials/{env}"
oidc = {}
with open(f"{cred}/oidc.env", encoding="utf-8-sig") as f:
    for line in f:
        if "=" in line and not line.startswith("#"):
            k, v = line.strip().split("=", 1)
            oidc[k] = v
sso = {}
with open(f"{cred}/sso-test-users.env", encoding="utf-8-sig") as f:
    for line in f:
        if "=" in line and not line.startswith("#"):
            k, v = line.strip().split("=", 1)
            sso[k] = v

client_id = "argocd"
secret = oidc.get("OIDC_ARGOCD_CLIENT_SECRET") or ""
user = sso.get("AM_ADMIN_TEST_USERNAME", "am-admin-test")
password = sso.get("AM_ADMIN_TEST_PASSWORD") or sso.get("am-admin-test")
if not secret or not password:
    print("missing client secret or test user password")
    sys.exit(2)

data = urllib.parse.urlencode(
    {
        "grant_type": "password",
        "client_id": client_id,
        "client_secret": secret,
        "username": user,
        "password": password,
        "scope": "openid profile email groups roles",
    }
).encode()
req = urllib.request.Request(
    f"{base}/realms/{realm}/protocol/openid-connect/token",
    data=data,
    method="POST",
    headers={"Content-Type": "application/x-www-form-urlencoded"},
)
try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        tok = json.loads(resp.read().decode())
except Exception as e:
    print("token_fail", type(e).__name__, getattr(e, "code", e))
    if hasattr(e, "read"):
        print(e.read().decode()[:300])
    sys.exit(1)

# decode JWT payload (no verify) for claims only
import base64

def payload(jwt):
    p = jwt.split(".")[1]
    p += "=" * (-len(p) % 4)
    return json.loads(base64.urlsafe_b64decode(p.encode()))

at = payload(tok["access_token"])
it = payload(tok.get("id_token") or tok["access_token"])
print("token_ok user=", user)
print("access.groups=", at.get("groups"))
print("access.roles=", at.get("roles"))
print("id.groups=", it.get("groups"))
print("id.roles=", it.get("roles"))
print("scope=", tok.get("scope"))
ok = bool(at.get("groups") or it.get("groups") or at.get("roles") or it.get("roles"))
sys.exit(0 if ok else 3)
