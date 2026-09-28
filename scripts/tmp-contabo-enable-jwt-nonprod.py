#!/usr/bin/env python3
"""Enable auth/jwt-nonprod on Contabo Vault and write laptop JWKS + role."""
import json, pathlib, subprocess, sys

tok = pathlib.Path("/tmp/am-vault-root.token").read_text().strip()
kc = "/root/.kube/config"
cfg = "/tmp/jwt-nonprod.json"
if not pathlib.Path(cfg).exists():
    print("MISSING", cfg); sys.exit(2)

def kexec(script: str, timeout=180):
    return subprocess.run(
        ["kubectl", "--kubeconfig", kc, "-n", "vault", "exec", "vault-0", "--", "sh", "-c", script],
        capture_output=True, text=True, timeout=timeout,
    )

# 1) List auth again
r = kexec(f"export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='{tok}'; vault auth list")
print(r.stdout or r.stderr)

# 2) Enable jwt-nonprod (ignore already in use)
r = kexec(
    f"export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='{tok}'; "
    "vault auth enable -path=jwt-nonprod jwt 2>&1 || true"
)
print("enable:", (r.stdout or "") + (r.stderr or ""))

# 3) Copy config into pod
subprocess.check_call(
    ["kubectl", "--kubeconfig", kc, "-n", "vault", "cp", cfg, "vault-0:/tmp/jwt-nonprod.json"]
)

# 4) Write config via API (curl/wget)
r = kexec(
    f"""
set -e
export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='{tok}'
if command -v curl >/dev/null 2>&1; then
  curl -sS -w '\\nHTTP:%{{http_code}}\\n' -H "X-Vault-Token: $VAULT_TOKEN" -H "Content-Type: application/json" \\
    --data @/tmp/jwt-nonprod.json http://127.0.0.1:8200/v1/auth/jwt-nonprod/config
else
  wget -qO- --header="X-Vault-Token: $VAULT_TOKEN" --header="Content-Type: application/json" \\
    --post-file=/tmp/jwt-nonprod.json http://127.0.0.1:8200/v1/auth/jwt-nonprod/config
  echo
fi
echo '--- config ---'
vault read auth/jwt-nonprod/config | head -30
"""
)
print("config_write:", r.stdout[-2500:] if r.stdout else "")
print("config_err:", (r.stderr or "")[-800:])
if r.returncode != 0:
    sys.exit(r.returncode)

# 5) Write role with proper JSON for bound_claims via API
role = {
    "role_type": "jwt",
    "user_claim": "sub",
    "bound_audiences": ["vault"],
    "bound_claims_type": "glob",
    "bound_claims": {"sub": "system:serviceaccount:am-*-dev:am-backend-sa"},
    "token_policies": ["am-backend-policy-dev"],
    "token_ttl": "1h",
    "token_type": "service",
}
role_path = "/tmp/jwt-nonprod-role.json"
pathlib.Path(role_path).write_text(json.dumps(role))
subprocess.check_call(
    ["kubectl", "--kubeconfig", kc, "-n", "vault", "cp", role_path, "vault-0:/tmp/jwt-nonprod-role.json"]
)
r = kexec(
    f"""
set -e
export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='{tok}'
# also ensure policy exists (best-effort)
vault policy read am-backend-policy-dev >/dev/null 2>&1 || vault policy write am-backend-policy-dev - <<'EOF'
path "apps/data/dev/*" {{
  capabilities = ["read"]
}}
path "apps/data/dev" {{
  capabilities = ["list"]
}}
path "apps/metadata/dev/*" {{
  capabilities = ["list", "read"]
}}
EOF
if command -v curl >/dev/null 2>&1; then
  curl -sS -w '\\nHTTP:%{{http_code}}\\n' -H "X-Vault-Token: $VAULT_TOKEN" -H "Content-Type: application/json" \\
    --data @/tmp/jwt-nonprod-role.json http://127.0.0.1:8200/v1/auth/jwt-nonprod/role/am-backend-role-dev
else
  wget -qO- --header="X-Vault-Token: $VAULT_TOKEN" --header="Content-Type: application/json" \\
    --post-file=/tmp/jwt-nonprod-role.json http://127.0.0.1:8200/v1/auth/jwt-nonprod/role/am-backend-role-dev
  echo
fi
echo '--- role ---'
vault read auth/jwt-nonprod/role/am-backend-role-dev | head -40
vault auth list | grep jwt
"""
)
print("role_write:", r.stdout[-3000:] if r.stdout else "")
print("role_err:", (r.stderr or "")[-800:])
sys.exit(r.returncode)
