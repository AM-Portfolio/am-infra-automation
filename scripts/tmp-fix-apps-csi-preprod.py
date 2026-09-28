import json, os, subprocess, urllib.request, urllib.error

VAULT = os.environ["VAULT_ADDR"].rstrip("/")
TOKEN = os.environ["VAULT_TOKEN"]
KC = os.environ["KUBECONFIG_APPS"]


def vault(method, path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(f"{VAULT}/v1/{path.lstrip('/')}", data=data, method=method)
    req.add_header("X-Vault-Token", TOKEN)
    req.add_header("User-Agent", "am-fix-csi/1.0")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            raw = r.read().decode() or "{}"
            return json.loads(raw) if raw.strip() else {}
    except urllib.error.HTTPError as e:
        err = e.read().decode()
        if e.code == 404:
            return None
        raise RuntimeError(f"{method} {path} -> {e.code} {err[:300]}")


jwks = subprocess.check_output(["kubectl", "--kubeconfig", KC, "get", "--raw", "/openid/v1/jwks"])
cfg = {
    "jwks_keys": jwks.decode(),
    "bound_issuer": "https://kubernetes.default.svc.cluster.local",
    "default_role": "am-laptop-csi",
}
try:
    vault("POST", "auth/jwt-laptop-apps/config", cfg)
    print("JWKS_UPDATED")
except Exception as e:
    print("JWKS_UPDATE_FAIL", e)

for envn in ("preprod", "dev"):
    for name, defaults in {
        "google": {"GOOGLE_CLIENT_ID": "placeholder", "GOOGLE_CLIENT_SECRET": "placeholder"},
        "cloudinary": {
            "CLOUDINARY_API_KEY": "placeholder",
            "CLOUDINARY_API_SECRET": "placeholder",
            "CLOUDINARY_CLOUD_NAME": "am",
        },
    }.items():
        sub = f"{envn}/shared/{name}"
        resp = vault("GET", f"apps/data/{sub}")
        cur = ((resp or {}).get("data") or {}).get("data") or {}
        if envn == "dev":
            src = vault("GET", f"apps/data/preprod/shared/{name}")
            for k, v in (((src or {}).get("data") or {}).get("data") or {}).items():
                cur.setdefault(k, v)
        for k, v in defaults.items():
            cur.setdefault(k, v)
        vault("POST", f"apps/data/{sub}", {"data": cur})
        print("ensured", f"apps/data/{sub}")

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
    new = objs
    new = new.replace("secret/data/dev/apps/docs/google", "apps/data/preprod/shared/google")
    new = new.replace("secret/data/dev/apps/docs/cloudinary", "apps/data/preprod/shared/cloudinary")
    new = new.replace("secret/data/preprod/apps/docs/google", "apps/data/preprod/shared/google")
    new = new.replace("secret/data/preprod/apps/docs/cloudinary", "apps/data/preprod/shared/cloudinary")
    new = new.replace("apps/data/dev/", "apps/data/preprod/")
    params["objects"] = new
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
        "spec": {
            "provider": spc["spec"].get("provider", "vault"),
            "parameters": params,
        },
    }
    if "secretObjects" in spc["spec"]:
        body["spec"]["secretObjects"] = spc["spec"]["secretObjects"]
    tmp = os.path.join(os.environ["TEMP"], f"spc-{name}.json")
    open(tmp, "w", encoding="utf-8").write(json.dumps(body))
    subprocess.check_call(["kubectl", "--kubeconfig", KC, "apply", "-f", tmp], stdout=subprocess.DEVNULL)
    n += 1
    print("SPC", name)
print("patched", n)

jwt = subprocess.check_output(
    ["kubectl", "--kubeconfig", KC, "-n", "am-apps-dev", "create", "token", "am-backend-sa", "--duration=10m"],
    text=True,
).strip()
login = vault("POST", "auth/jwt-laptop-apps/login", {"role": "am-laptop-csi", "jwt": jwt})
ct = login["auth"]["client_token"]
print("JWT_LOGIN_OK", login["auth"].get("policies"))


def csi_get(path):
    req = urllib.request.Request(f"{VAULT}/v1/{path}")
    req.add_header("X-Vault-Token", ct)
    req.add_header("User-Agent", "am-fix-csi/1.0")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())


for p in (
    "apps/data/preprod/services/am-identity",
    "apps/data/preprod/shared/google",
    "apps/data/preprod/shared/cloudinary",
):
    d = (csi_get(p).get("data") or {}).get("data") or {}
    print("READ_OK", p, "keys", len(d))
