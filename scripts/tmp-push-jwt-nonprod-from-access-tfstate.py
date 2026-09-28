#!/usr/bin/env python3
"""Update Contabo jwt-nonprod with laptop Kind JWKS using root from access.tfstate on VPS."""
import base64, json, os, pathlib, subprocess, sys, textwrap

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

SSH_BASE = [
    "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=30",
    "-p", "7576", "-i", os.path.expanduser("~/.ssh/id_ed25519_hts_vps"),
    "root@103.127.146.57",
]
SCP_BASE = [
    "scp", "-P", "7576", "-i", os.path.expanduser("~/.ssh/id_ed25519_hts_vps"),
    "-o", "StrictHostKeyChecking=no",
]
kc_apps = os.path.expanduser("~/.asrax/kubeconfig.am-dev-apps.yaml")
tmpdir = pathlib.Path(os.environ.get("TEMP") or "/tmp")

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

payload = {
    "jwt_validation_pubkeys": pubkeys,
    "bound_issuer": "https://kubernetes.default.svc.cluster.local",
    "default_role": "am-backend-role-dev",
    "jwks_url": "",
    "oidc_discovery_url": "",
}
cfg_path = tmpdir / "jwt-nonprod.json"
cfg_path.write_text(json.dumps(payload), encoding="utf-8")
subprocess.check_call(SCP_BASE + [str(cfg_path), "root@103.127.146.57:/tmp/jwt-nonprod.json"])

remote = textwrap.dedent(
    r"""
    set -euo pipefail
    TOK=$(cat /tmp/am-vault-root.token)
    KC=/root/.kube/config
    kubectl --kubeconfig "$KC" -n vault cp /tmp/jwt-nonprod.json vault-0:/tmp/jwt-nonprod.json
    kubectl --kubeconfig "$KC" -n vault exec vault-0 -- sh -c "
      set -e
      export VAULT_ADDR=http://127.0.0.1:8200
      export VAULT_TOKEN='$TOK'
      # Prefer curl; fall back to wget
      if command -v curl >/dev/null 2>&1; then
        curl -sS -f -H \"X-Vault-Token: \$VAULT_TOKEN\" -H 'Content-Type: application/json' \
          --data @/tmp/jwt-nonprod.json http://127.0.0.1:8200/v1/auth/jwt-nonprod/config
      else
        wget -qO- --header=\"X-Vault-Token: \$VAULT_TOKEN\" --header='Content-Type: application/json' \
          --post-file=/tmp/jwt-nonprod.json http://127.0.0.1:8200/v1/auth/jwt-nonprod/config
      fi
      echo
      vault read auth/jwt-nonprod/config | head -30
    "
    echo WRITE_OK
    """
).strip()
r = subprocess.run(SSH_BASE + [remote], capture_output=True, text=True)
print(r.stdout[-1500:])
if r.returncode != 0:
    print(r.stderr[-800:], file=sys.stderr)
    sys.exit(r.returncode)

# canary SA login through vault-0
jwt = subprocess.check_output(
    [
        "kubectl", "--kubeconfig", kc_apps, "-n", "am-apps-dev",
        "create", "token", "am-backend-sa", "--audience=vault", "--duration=10m",
    ],
    text=True,
).strip()
(tmpdir / "sa.jwt").write_text(jwt, encoding="utf-8")
subprocess.check_call(SCP_BASE + [str(tmpdir / "sa.jwt"), "root@103.127.146.57:/tmp/sa.jwt"])
login = textwrap.dedent(
    r"""
    set -euo pipefail
    JWT=$(cat /tmp/sa.jwt)
    kubectl --kubeconfig /root/.kube/config -n vault exec vault-0 -- \
      sh -c "VAULT_ADDR=http://127.0.0.1:8200 vault write -format=json auth/jwt-nonprod/login role=am-backend-role-dev jwt=\"$JWT\"" \
      | python3 -c "import sys,json; a=json.load(sys.stdin).get('auth') or {}; print('LOGIN_OK', a.get('policies'))"
    """
).strip()
r2 = subprocess.run(SSH_BASE + [login], capture_output=True, text=True)
print(r2.stdout)
if "LOGIN_OK" not in (r2.stdout or ""):
    print(r2.stderr[-600:], file=sys.stderr)
    sys.exit(1)
print("DONE")
