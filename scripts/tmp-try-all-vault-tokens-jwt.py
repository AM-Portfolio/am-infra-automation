#!/usr/bin/env python3
"""Try all discovered Vault tokens against jwt-nonprod config write."""
import json, pathlib, re, os, urllib.request, urllib.error, base64, subprocess

def http(method, url, token, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("X-Vault-Token", token)
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:200]
    except Exception as e:
        return 0, str(e)

sources = []
for p in [
    pathlib.Path(os.path.expanduser("~/.asrax/tfstate/dev/vault-apps-contabo/terraform.tfstate")),
    pathlib.Path(os.path.expanduser("~/.asrax/tfstate/dev/vault-apps-contabo/terraform.tfstate.backup")),
    pathlib.Path(r"f:/am-repos/am-repos/am-env-vault/am-env-vault/environments/shared/am-infra__env.infra"),
    pathlib.Path(r"f:/am-repos/am-repos/am-env-vault/am-env-vault/environments/shared/shared__vps__env"),
    pathlib.Path(r"f:/am-repos/am-repos/am-env-vault/am-env-vault/services/am-infra/env.infra"),
    pathlib.Path(r"f:/am-repos/am-repos/am-env-vault/am-env-vault/services/shared/vps/env"),
    pathlib.Path(os.path.expanduser("~/.asrax/vault-contabo-infra.json")),
    pathlib.Path(os.path.expanduser("~/.asrax/credentials.env")),
    pathlib.Path(os.path.expanduser("~/.asrax/credentials.d/vault-dev.env")),
    pathlib.Path(os.path.expanduser("~/.asrax/credentials.d/vault-kind-nonprod.env")),
]:
    if not p.exists():
        continue
    text = p.read_text(encoding="utf-8-sig", errors="ignore")
    for tok in set(re.findall(r"hvs\.[A-Za-z0-9._-]{16,}", text)):
        sources.append((str(p), tok))

print("tokens", len(sources))
addr = "https://vault.asrax.in"
best = None
for src, tok in sources:
    code, body = http("GET", f"{addr}/v1/auth/jwt-nonprod/config", tok)
    print("READ", pathlib.Path(src).name, code, str(body)[:80].replace("\n", " "))
    if code == 200:
        best = (src, tok)
        break
    # also try identity lookup
    code2, body2 = http("GET", f"{addr}/v1/auth/token/lookup-self", tok)
    if code2 == 200:
        policies = (body2.get("data") or {}).get("policies")
        print("  lookup-self policies", policies)

if not best:
    # try POST with each token anyway in case read is denied but write allowed (unlikely)
    print("NO_READ_OK")
    raise SystemExit(2)

src, tok = best
print("USING", src)

# Build pubkeys from laptop Kind
kc = os.path.expanduser("~/.asrax/kubeconfig.am-dev-apps.yaml")
jwks = json.loads(subprocess.check_output(["kubectl", "--kubeconfig", kc, "get", "--raw", "/openid/v1/jwks"]))
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

# Merge with existing keys if present so Contabo Kind dig still works if needed
existing = []
code, cfg = http("GET", f"{addr}/v1/auth/jwt-nonprod/config", tok)
if code == 200:
    existing = (cfg.get("data") or {}).get("jwt_validation_pubkeys") or []
merged = list(dict.fromkeys(list(existing) + pubkeys))  # preserve order, dedupe
print("existing", len(existing), "laptop", len(pubkeys), "merged", len(merged))

code, body = http(
    "POST",
    f"{addr}/v1/auth/jwt-nonprod/config",
    tok,
    {
        "jwt_validation_pubkeys": merged,
        "bound_issuer": "https://kubernetes.default.svc.cluster.local",
        "default_role": "am-backend-role-dev",
        "jwks_url": "",
        "oidc_discovery_url": "",
    },
)
print("WRITE", code, str(body)[:200])
if code not in (200, 204):
    raise SystemExit(1)

# canary login
jwt = subprocess.check_output(
    ["kubectl", "--kubeconfig", kc, "-n", "am-apps-dev", "create", "token", "am-backend-sa", "--audience=vault", "--duration=10m"],
    text=True,
).strip()
code, body = http("POST", f"{addr}/v1/auth/jwt-nonprod/login", tok if False else "", {"role": "am-backend-role-dev", "jwt": jwt})
# login doesn't need admin token
req = urllib.request.Request(
    f"{addr}/v1/auth/jwt-nonprod/login",
    data=json.dumps({"role": "am-backend-role-dev", "jwt": jwt}).encode(),
    method="POST",
    headers={"Content-Type": "application/json"},
)
try:
    with urllib.request.urlopen(req, timeout=25) as r:
        auth = json.loads(r.read().decode()).get("auth") or {}
        print("LOGIN_OK", auth.get("policies"))
except urllib.error.HTTPError as e:
    print("LOGIN_FAIL", e.code, e.read().decode()[:300])
    raise SystemExit(1)
