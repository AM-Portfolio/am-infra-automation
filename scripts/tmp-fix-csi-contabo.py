import json, os, subprocess, urllib.request, urllib.error, base64, time
from pathlib import Path

VAULT = "https://vault.asrax.in"
KC = os.path.expanduser(r"~\.asrax\kubeconfig.am-dev-apps.yaml")
TOKEN = Path(os.environ["TEMP"], "contabo-vault.ok").read_text(encoding="utf-8").splitlines()[1].strip()


def vault(method, path, body=None, retries=4):
    last = None
    for i in range(retries):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(f"{VAULT}/v1/{path}", data=data, method=method)
        req.add_header("X-Vault-Token", TOKEN)
        req.add_header("User-Agent", "am-contabo-csi/1.0")
        if data:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=45) as r:
                return json.loads(r.read().decode() or "{}")
        except urllib.error.HTTPError as e:
            err = e.read().decode()
            if e.code in (502, 503, 504):
                time.sleep(2 + i)
                last = e
                continue
            if e.code == 404:
                return None
            raise RuntimeError(f"{method} {path} {e.code} {err[:300]}")
        except Exception as e:
            last = e
            time.sleep(2 + i)
    raise RuntimeError(str(last))


# Ensure jwt auth mount/role exists; refresh pubkeys from this Kind cluster
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

# enable auth if needed - ignore errors
try:
    vault("POST", "sys/auth/jwt-laptop-apps", {"type": "jwt", "description": "laptop kind apps CSI"})
    print("AUTH_ENABLED")
except Exception as e:
    print("AUTH_EXISTS_OR", str(e)[:120])

vault(
    "POST",
    "auth/jwt-laptop-apps/config",
    {
        "jwt_validation_pubkeys": pubkeys,
        "bound_issuer": "https://kubernetes.default.svc.cluster.local",
        "default_role": "am-laptop-csi",
        "jwks_url": "",
        "oidc_discovery_url": "",
    },
)
print("JWT_CONFIG_OK")

# Role + policy (idempotent)
policy = """
path "apps/data/prod/*" { capabilities = ["read","list"] }
path "apps/metadata/prod/*" { capabilities = ["list","read"] }
path "apps/data/preprod/*" { capabilities = ["read","list"] }
path "apps/metadata/preprod/*" { capabilities = ["list","read"] }
path "apps/data/dev/*" { capabilities = ["read","list"] }
path "apps/metadata/dev/*" { capabilities = ["list","read"] }
path "secret/data/*" { capabilities = ["read","list"] }
path "secret/metadata/*" { capabilities = ["list","read"] }
"""
vault("PUT", "sys/policy/am-laptop-csi", {"policy": policy})
vault(
    "POST",
    "auth/jwt-laptop-apps/role/am-laptop-csi",
    {
        "role_type": "jwt",
        "bound_audiences": ["https://kubernetes.default.svc.cluster.local"],
        "user_claim": "sub",
        "bound_claims_type": "glob",
        "bound_claims": {"sub": "system:serviceaccount:am-*:am-backend-sa"},
        "token_policies": ["am-laptop-csi"],
        "token_ttl": "15m",
        "token_max_ttl": "1h",
    },
)
print("ROLE_OK")

jwt = subprocess.check_output(
    ["kubectl", "--kubeconfig", KC, "-n", "am-apps-dev", "create", "token", "am-backend-sa", "--duration=10m"],
    text=True,
).strip()
login = vault("POST", "auth/jwt-laptop-apps/login", {"role": "am-laptop-csi", "jwt": jwt})
ct = login["auth"]["client_token"]
print("LOGIN_OK", login["auth"].get("policies"))

# Ensure shared paths on Contabo preprod
for name, defaults in {
    "google": {"GOOGLE_CLIENT_ID": "placeholder", "GOOGLE_CLIENT_SECRET": "placeholder"},
    "cloudinary": {
        "CLOUDINARY_API_KEY": "placeholder",
        "CLOUDINARY_API_SECRET": "placeholder",
        "CLOUDINARY_CLOUD_NAME": "am",
    },
}.items():
    sub = f"preprod/shared/{name}"
    resp = vault("GET", f"apps/data/{sub}")
    cur = ((resp or {}).get("data") or {}).get("data") or {}
    for k, v in defaults.items():
        cur.setdefault(k, v)
    vault("POST", f"apps/data/{sub}", {"data": cur})
    print("ensured", sub, len(cur))

# Point all SPCs at Contabo vault (keep preprod paths)
spcs = json.loads(
    subprocess.check_output(
        ["kubectl", "--kubeconfig", KC, "-n", "am-apps-dev", "get", "secretproviderclass", "-o", "json"]
    )
)
n = 0
for spc in spcs["items"]:
    name = spc["metadata"]["name"]
    params = dict(spc["spec"].get("parameters") or {})
    objs = params.get("objects") or ""
    objs = objs.replace("secret/data/dev/apps/docs/google", "apps/data/preprod/shared/google")
    objs = objs.replace("secret/data/dev/apps/docs/cloudinary", "apps/data/preprod/shared/cloudinary")
    objs = objs.replace("apps/data/dev/", "apps/data/preprod/")
    params["objects"] = objs
    params["vaultAddress"] = VAULT
    params["vaultAuthMountPath"] = "jwt-laptop-apps"
    params["roleName"] = "am-laptop-csi"
    params.pop("roleID", None)
    params.pop("secretID", None)
    params["vaultCACertGen"] = "false"
    body = {
        "apiVersion": "secrets-store.csi.x-k8s.io/v1",
        "kind": "SecretProviderClass",
        "metadata": {"name": name, "namespace": "am-apps-dev"},
        "spec": {"provider": "vault", "parameters": params},
    }
    if "secretObjects" in spc["spec"]:
        body["spec"]["secretObjects"] = spc["spec"]["secretObjects"]
    tmp = Path(os.environ["TEMP"]) / f"spc-{name}.json"
    tmp.write_text(json.dumps(body), encoding="utf-8")
    subprocess.check_call(["kubectl", "--kubeconfig", KC, "apply", "-f", str(tmp)], stdout=subprocess.DEVNULL)
    n += 1
print("SPC_PATCHED", n, "->", VAULT)

# CSI token read smoke
req = urllib.request.Request(f"{VAULT}/v1/apps/data/preprod/services/am-identity")
req.add_header("X-Vault-Token", ct)
req.add_header("User-Agent", "am-contabo-csi/1.0")
with urllib.request.urlopen(req, timeout=30) as r:
    d = (json.loads(r.read().decode()).get("data") or {}).get("data") or {}
print("CSI_READ_identity", len(d))
