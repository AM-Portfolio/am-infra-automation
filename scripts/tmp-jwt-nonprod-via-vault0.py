#!/usr/bin/env python3
"""Update Contabo auth/jwt-nonprod pubkeys from laptop Kind JWKS via vault-0 exec."""
import base64, json, os, pathlib, subprocess, sys, tempfile

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

kc_apps = os.path.expanduser("~/.asrax/kubeconfig.am-dev-apps.yaml")
kc_vps = os.path.expanduser("~/.asrax/kubeconfig.am-vps-nonprod.yaml")
root = json.loads(
    pathlib.Path(os.path.expanduser("~/.asrax/vault-contabo-infra.json")).read_text(encoding="utf-8-sig")
)["root_token"]

jwks = json.loads(
    subprocess.check_output(["kubectl", "--kubeconfig", kc_apps, "get", "--raw", "/openid/v1/jwks"])
)
pubkeys = []
for jwk in jwks.get("keys", []):
    n = int.from_bytes(base64.urlsafe_b64decode(jwk["n"] + "=="), "big")
    e = int.from_bytes(base64.urlsafe_b64decode(jwk["e"] + "=="), "big")
    pub = rsa.RSAPublicNumbers(e, n).public_key(default_backend())
    pem = pub.public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo
    ).decode()
    pubkeys.append(pem)
print("laptop_pubkeys", len(pubkeys))

# Verify token inside vault-0
r = subprocess.run(
    [
        "kubectl",
        "--kubeconfig",
        kc_vps,
        "-n",
        "vault",
        "exec",
        "vault-0",
        "--",
        "sh",
        "-c",
        f"export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN={root}; vault token lookup -format=json",
    ],
    capture_output=True,
    text=True,
)
if r.returncode != 0:
    print("token_lookup_fail", r.stderr[:500], file=sys.stderr)
    sys.exit(1)
print("token_lookup_ok", (json.loads(r.stdout).get("data") or {}).get("policies"))

payload = {
    "jwt_validation_pubkeys": pubkeys,
    "bound_issuer": "https://kubernetes.default.svc.cluster.local",
    "default_role": "am-backend-role-dev",
    "jwks_url": "",
    "oidc_discovery_url": "",
}
body = json.dumps(payload)

# Copy JSON into pod and POST with vault CLI (vault write accepts JSON via stdin with -)
inner = f"""set -e
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN={root}
cat >/tmp/jwt-nonprod.json <<'EOF'
{body}
EOF
vault write -format=json auth/jwt-nonprod/config @/tmp/jwt-nonprod.json
# canary login from a projected token is done on laptop side
vault read -format=json auth/jwt-nonprod/config | head -c 400
echo
"""
r2 = subprocess.run(
    ["kubectl", "--kubeconfig", kc_vps, "-n", "vault", "exec", "-i", "vault-0", "--", "sh", "-c", inner],
    capture_output=True,
    text=True,
)
print(r2.stdout[-800:] if r2.stdout else "")
if r2.returncode != 0:
    print(r2.stderr[-800:], file=sys.stderr)
    sys.exit(r2.returncode)

# Canary JWT login from laptop Kind SA
jwt = subprocess.check_output(
    [
        "kubectl",
        "--kubeconfig",
        kc_apps,
        "-n",
        "am-apps-dev",
        "create",
        "token",
        "am-backend-sa",
        "--audience=vault",
        "--duration=10m",
    ],
    text=True,
).strip()
# Login via vault-0 (public vault.asrax.in may 403 our tokens)
login_inner = f"""export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN={root}
vault write -format=json auth/jwt-nonprod/login role=am-backend-role-dev jwt='{jwt}'
"""
r3 = subprocess.run(
    ["kubectl", "--kubeconfig", kc_vps, "-n", "vault", "exec", "vault-0", "--", "sh", "-c", login_inner],
    capture_output=True,
    text=True,
)
if r3.returncode != 0:
    print("LOGIN_FAIL", r3.stderr[-500:], file=sys.stderr)
    sys.exit(1)
auth = json.loads(r3.stdout).get("auth") or {}
print("LOGIN_OK", auth.get("policies"))
