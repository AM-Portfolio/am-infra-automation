"""Update Contabo auth/jwt-nonprod with laptop Kind JWKS pubkeys (dig CSI)."""
import json, os, subprocess, urllib.request, urllib.error, base64, time, pathlib

VAULT = os.environ.get("VAULT_ADDR", "https://vault.asrax.in").rstrip("/")
KC = os.environ.get("KUBECONFIG_APPS") or os.path.expanduser("~/.asrax/kubeconfig.am-dev-apps.yaml")

def load_vault_token():
    if os.environ.get("VAULT_TOKEN"):
        return os.environ["VAULT_TOKEN"]
    p = pathlib.Path(os.path.expanduser("~/.asrax/credentials.env"))
    vals = {}
    for line in p.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        vals[k.strip()] = v.strip().strip('"').strip("'")
    for k in ("VAULT_TOKEN", "VAULT_ROOT_TOKEN", "CONTABO_VAULT_TOKEN"):
        if vals.get(k):
            return vals[k]
    raise SystemExit("No VAULT_TOKEN in env or credentials.env")

TOKEN = load_vault_token()

def vault(method, path, body=None, retries=5):
    last = None
    for i in range(retries):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(f"{VAULT}/v1/{path}", data=data, method=method)
        req.add_header("X-Vault-Token", TOKEN)
        req.add_header("User-Agent", "am-jwt-nonprod-laptop/1.0")
        if data:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=45) as r:
                return json.loads(r.read().decode() or "{}")
        except urllib.error.HTTPError as e:
            last = e
            if e.code in (502, 503, 504):
                time.sleep(2 + i)
                continue
            raise RuntimeError(f"{method} {path} {e.code} {e.read().decode()[:300]}")
        except Exception as e:
            last = e
            time.sleep(2 + i)
    raise RuntimeError(str(last))

from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend

jwks = json.loads(subprocess.check_output(["kubectl", "--kubeconfig", KC, "get", "--raw", "/openid/v1/jwks"]))
pubkeys = []
for jwk in jwks.get("keys", []):
    n = int.from_bytes(base64.urlsafe_b64decode(jwk["n"] + "=="), "big")
    e = int.from_bytes(base64.urlsafe_b64decode(jwk["e"] + "=="), "big")
    pub = rsa.RSAPublicNumbers(e, n).public_key(default_backend())
    pem = pub.public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo).decode()
    pubkeys.append(pem)
    print("PUB", jwk.get("kid"), len(pem))

# Read existing config; replace pubkeys with laptop Kind keys (Contabo dig abandoned)
cfg = vault("GET", "auth/jwt-nonprod/config")
print("BEFORE keys", len((cfg.get("data") or {}).get("jwt_validation_pubkeys") or []))

vault("POST", "auth/jwt-nonprod/config", {
    "jwt_validation_pubkeys": pubkeys,
    "bound_issuer": "https://kubernetes.default.svc.cluster.local",
    "default_role": "am-backend-role-dev",
    "jwks_url": "",
    "oidc_discovery_url": "",
})
print("UPDATED jwt-nonprod with laptop Kind pubkeys")

jwt = subprocess.check_output(
    ["kubectl", "--kubeconfig", KC, "-n", "am-apps-dev", "create", "token", "am-backend-sa",
     "--audience=vault", "--duration=10m"],
    text=True,
).strip()
login = vault("POST", "auth/jwt-nonprod/login", {"role": "am-backend-role-dev", "jwt": jwt})
print("LOGIN_OK", login["auth"].get("policies"))
