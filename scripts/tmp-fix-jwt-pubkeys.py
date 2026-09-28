import json, os, subprocess, urllib.request, urllib.error, base64, time

VAULT = os.environ["VAULT_ADDR"].rstrip("/")
TOKEN = os.environ["VAULT_TOKEN"]
KC = os.environ["KUBECONFIG_APPS"]

def vault(method, path, body=None, retries=5):
    last = None
    for i in range(retries):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(f"{VAULT}/v1/{path}", data=data, method=method)
        req.add_header("X-Vault-Token", TOKEN)
        req.add_header("User-Agent", "am-jwt-fix/1.0")
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

cfg = vault("GET", "auth/jwt-laptop-apps/config")
print("CURRENT", {k: (str(v)[:80] if v else v) for k, v in (cfg.get("data") or {}).items() if k in ("jwks_url","oidc_discovery_url","jwt_validation_pubkeys","bound_issuer","default_role")})

jwks = json.loads(subprocess.check_output(["kubectl", "--kubeconfig", KC, "get", "--raw", "/openid/v1/jwks"]))
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend

pubkeys = []
for jwk in jwks.get("keys", []):
    n = int.from_bytes(base64.urlsafe_b64decode(jwk["n"] + "=="), "big")
    e = int.from_bytes(base64.urlsafe_b64decode(jwk["e"] + "=="), "big")
    pub = rsa.RSAPublicNumbers(e, n).public_key(default_backend())
    pem = pub.public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo).decode()
    pubkeys.append(pem)
    print("PUB", jwk.get("kid"), len(pem))

vault("POST", "auth/jwt-laptop-apps/config", {
    "jwt_validation_pubkeys": pubkeys,
    "bound_issuer": "https://kubernetes.default.svc.cluster.local",
    "default_role": "am-laptop-csi",
    "jwks_url": "",
    "oidc_discovery_url": "",
})
print("UPDATED")

jwt = subprocess.check_output(["kubectl", "--kubeconfig", KC, "-n", "am-apps-dev", "create", "token", "am-backend-sa", "--duration=10m"], text=True).strip()
login = vault("POST", "auth/jwt-laptop-apps/login", {"role": "am-laptop-csi", "jwt": jwt})
print("LOGIN_OK", login["auth"].get("policies"))
