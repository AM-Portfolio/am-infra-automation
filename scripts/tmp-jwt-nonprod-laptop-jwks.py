#!/usr/bin/env python3
"""Merge laptop Kind JWKS into Contabo auth/jwt-nonprod via VPS vault-0."""
from __future__ import annotations

import base64
import json
import os
import pathlib
import subprocess
import sys

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

HOME = pathlib.Path.home()
SSH = [
    "ssh",
    "-o",
    "BatchMode=yes",
    "-o",
    "ConnectTimeout=30",
    "-p",
    "7576",
    "-i",
    str(HOME / ".ssh" / "id_ed25519_hts_vps"),
    "root@103.127.146.57",
]
SCP = [
    "scp",
    "-P",
    "7576",
    "-i",
    str(HOME / ".ssh" / "id_ed25519_hts_vps"),
    "-o",
    "StrictHostKeyChecking=no",
]
TMP = pathlib.Path(os.environ.get("TEMP") or "/tmp")
KC = str(HOME / ".asrax" / "kubeconfig.dev.local")


def main() -> int:
    tok = json.loads((HOME / ".asrax" / "vault-contabo-infra.json").read_text(encoding="utf-8-sig"))[
        "root_token"
    ]
    jwks = json.loads(
        subprocess.check_output(["kubectl", "--kubeconfig", KC, "get", "--raw", "/openid/v1/jwks"])
    )
    pubkeys: list[str] = []
    for jwk in jwks.get("keys", []):
        n = int.from_bytes(base64.urlsafe_b64decode(jwk["n"] + "=="), "big")
        e = int.from_bytes(base64.urlsafe_b64decode(jwk["e"] + "=="), "big")
        pub = rsa.RSAPublicNumbers(e, n).public_key(default_backend())
        pem = pub.public_bytes(
            serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo
        ).decode()
        pubkeys.append(pem)
    print("laptop_pubkeys", len(pubkeys))

    token_path = TMP / "am-vault-root.token"
    new_path = TMP / "jwt-nonprod-new.json"
    token_path.write_text(tok, encoding="utf-8")
    new_path.write_text(
        json.dumps(
            {
                "jwt_validation_pubkeys": pubkeys,
                "bound_issuer": "https://kubernetes.default.svc.cluster.local",
                "default_role": "am-backend-role-dev",
                "jwks_url": "",
                "oidc_discovery_url": "",
            }
        ),
        encoding="utf-8",
    )
    subprocess.check_call(SCP + [str(token_path), "root@103.127.146.57:/tmp/am-vault-root.token"])
    subprocess.check_call(SCP + [str(new_path), "root@103.127.146.57:/tmp/jwt-nonprod-new.json"])

    remote = r"""
set -euo pipefail
TOK=$(cat /tmp/am-vault-root.token)
KC=/root/.kube/config
kubectl --kubeconfig "$KC" -n vault exec vault-0 -- \
  env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="$TOK" \
  vault read -format=json auth/jwt-nonprod/config > /tmp/jwt-old.json \
  || echo '{}' > /tmp/jwt-old.json
python3 - <<'PY'
import json
from pathlib import Path
try:
    old = (json.loads(Path("/tmp/jwt-old.json").read_text()) or {}).get("data") or {}
except Exception:
    old = {}
new = json.loads(Path("/tmp/jwt-nonprod-new.json").read_text())
merged = list(
    dict.fromkeys((old.get("jwt_validation_pubkeys") or []) + (new.get("jwt_validation_pubkeys") or []))
)
out = {
    "jwt_validation_pubkeys": merged,
    "bound_issuer": new.get("bound_issuer")
    or old.get("bound_issuer")
    or "https://kubernetes.default.svc.cluster.local",
    "default_role": "am-backend-role-dev",
    "jwks_url": "",
    "oidc_discovery_url": "",
}
Path("/tmp/jwt-nonprod.json").write_text(json.dumps(out))
print("merged_keys", len(merged))
PY
kubectl --kubeconfig "$KC" -n vault cp /tmp/jwt-nonprod.json vault-0:/tmp/jwt-nonprod.json
kubectl --kubeconfig "$KC" -n vault exec vault-0 -- sh -c '
  set -e
  export VAULT_ADDR=http://127.0.0.1:8200
  export VAULT_TOKEN=$(cat /tmp/am-vault-root.token 2>/dev/null || true)
'
# token must be inside pod — copy it
kubectl --kubeconfig "$KC" -n vault cp /tmp/am-vault-root.token vault-0:/tmp/am-vault-root.token
kubectl --kubeconfig "$KC" -n vault exec vault-0 -- sh -c '
  set -e
  export VAULT_ADDR=http://127.0.0.1:8200
  export VAULT_TOKEN=$(cat /tmp/am-vault-root.token)
  curl -sS -f -H "X-Vault-Token: $VAULT_TOKEN" -H "Content-Type: application/json" \
    --data @/tmp/jwt-nonprod.json http://127.0.0.1:8200/v1/auth/jwt-nonprod/config
  echo
  vault read auth/jwt-nonprod/config | head -20
  rm -f /tmp/am-vault-root.token
'
echo WRITE_OK
"""
    r = subprocess.run(SSH + [remote.strip()], capture_output=True, text=True)
    sys.stdout.write(r.stdout[-2500:])
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-1500:])
        return r.returncode

    jwt = subprocess.check_output(
        [
            "kubectl",
            "--kubeconfig",
            KC,
            "-n",
            "am-agents-dev",
            "create",
            "token",
            "am-backend-sa",
            "--audience=vault",
            "--duration=10m",
        ],
        text=True,
    ).strip()
    (TMP / "sa.jwt").write_text(jwt, encoding="utf-8")
    subprocess.check_call(SCP + [str(TMP / "sa.jwt"), "root@103.127.146.57:/tmp/sa.jwt"])
    login = r"""
set -euo pipefail
JWT=$(cat /tmp/sa.jwt)
kubectl --kubeconfig /root/.kube/config -n vault exec vault-0 -- \
  env VAULT_ADDR=http://127.0.0.1:8200 \
  vault write -format=json auth/jwt-nonprod/login role=am-backend-role-dev jwt="$JWT" \
  | python3 -c "import sys,json; a=json.load(sys.stdin).get('auth') or {}; print('LOGIN_OK', a.get('policies'))"
"""
    r2 = subprocess.run(SSH + [login.strip()], capture_output=True, text=True)
    sys.stdout.write(r2.stdout)
    if "LOGIN_OK" not in (r2.stdout or ""):
        sys.stderr.write(r2.stderr[-800:])
        return 1
    print("DONE")
    token_path.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
