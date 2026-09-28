#!/usr/bin/env python3
"""On Contabo: list auth mounts, ensure jwt-nonprod, write laptop JWKS."""
import json, pathlib, subprocess, sys

tok = pathlib.Path("/tmp/am-vault-root.token").read_text().strip()
kc = "/root/.kube/config"
cfg = pathlib.Path("/tmp/jwt-nonprod.json")
if not cfg.exists():
    print("MISSING /tmp/jwt-nonprod.json — scp from laptop first")
    sys.exit(2)

def kexec(script: str):
    return subprocess.run(
        ["kubectl", "--kubeconfig", kc, "-n", "vault", "exec", "vault-0", "--", "sh", "-c", script],
        capture_output=True,
        text=True,
        timeout=120,
    )

r = kexec(f"export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='{tok}'; vault auth list -format=json")
print("auth_list_rc", r.returncode)
if r.returncode != 0:
    print(r.stderr[:800])
    sys.exit(1)
auths = json.loads(r.stdout or "{}")
print("auth_mounts", list(auths.keys()))

mount = None
for name in auths:
    n = name.rstrip("/")
    if n in ("jwt-nonprod", "jwt", "jwt-laptop-apps"):
        mount = n
        print("found", n, "type", (auths[name] or {}).get("type"))
if mount is None:
    # enable jwt-nonprod
    print("enabling auth/jwt-nonprod")
    r2 = kexec(
        f"export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='{tok}'; "
        "vault auth enable -path=jwt-nonprod jwt"
    )
    print(r2.stdout or r2.stderr)
    if r2.returncode != 0 and "path is already in use" not in (r2.stderr or ""):
        sys.exit(r2.returncode)
    mount = "jwt-nonprod"

# cp config into pod and POST
subprocess.check_call(
    ["kubectl", "--kubeconfig", kc, "-n", "vault", "cp", "/tmp/jwt-nonprod.json", "vault-0:/tmp/jwt-nonprod.json"]
)
write = kexec(
    f"""
set -e
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN='{tok}'
if command -v curl >/dev/null 2>&1; then
  curl -sS -f -H "X-Vault-Token: $VAULT_TOKEN" -H "Content-Type: application/json" \
    --data @/tmp/jwt-nonprod.json http://127.0.0.1:8200/v1/auth/{mount}/config
else
  wget -qO- --header="X-Vault-Token: $VAULT_TOKEN" --header="Content-Type: application/json" \
    --post-file=/tmp/jwt-nonprod.json http://127.0.0.1:8200/v1/auth/{mount}/config
fi
echo
vault read auth/{mount}/config | head -25
# ensure role exists
vault read auth/{mount}/role/am-backend-role-dev >/dev/null 2>&1 || \
  vault write auth/{mount}/role/am-backend-role-dev \
    role_type=jwt \
    user_claim=sub \
    bound_audiences=vault \
    bound_subject="" \
    bound_claims_type=glob \
    bound_claims='{{"sub":"system:serviceaccount:am-*-dev:am-backend-sa"}}' \
    token_policies=am-backend-policy-dev \
    token_ttl=1h
vault read auth/{mount}/role/am-backend-role-dev | head -20
"""
)
print(write.stdout[-2000:])
print(write.stderr[-500:] if write.stderr else "")
sys.exit(write.returncode)
