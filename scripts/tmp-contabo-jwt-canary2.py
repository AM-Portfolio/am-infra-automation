#!/usr/bin/env python3
"""Canary login via vault CLI + wget inside vault-0."""
import json, pathlib, subprocess, sys

tok = pathlib.Path("/tmp/am-vault-root.token").read_text().strip()
jwt = pathlib.Path("/tmp/sa-jwt.txt").read_text().strip()
kc = "/root/.kube/config"
payload = json.dumps({"role": "am-backend-role-dev", "jwt": jwt})
pathlib.Path("/tmp/login.json").write_text(payload)
subprocess.check_call(
    ["kubectl", "--kubeconfig", kc, "-n", "vault", "cp", "/tmp/login.json", "vault-0:/tmp/login.json"]
)
# also put jwt alone for vault write
pathlib.Path("/tmp/sa-jwt-only.txt").write_text(jwt)
subprocess.check_call(
    ["kubectl", "--kubeconfig", kc, "-n", "vault", "cp", "/tmp/sa-jwt-only.txt", "vault-0:/tmp/sa-jwt.txt"]
)

def kexec(script):
    return subprocess.run(
        ["kubectl", "--kubeconfig", kc, "-n", "vault", "exec", "vault-0", "--", "sh", "-c", script],
        capture_output=True, text=True, timeout=90,
    )

# detect tools
r = kexec("command -v wget; command -v vault; ls /bin /usr/bin 2>/dev/null | head")
print("tools:", r.stdout)

for mount in ("jwt-nonprod", "jwt-laptop-apps"):
    r = kexec(
        f"""
export VAULT_ADDR=http://127.0.0.1:8200
JWT=$(cat /tmp/sa-jwt.txt)
vault write -format=json auth/{mount}/login role=am-backend-role-dev jwt="$JWT" 2>&1 | head -c 2000
echo EXIT:$?
"""
    )
    print(f"=== vault write {mount} ===")
    print(r.stdout[-2000:] if r.stdout else "")
    print(r.stderr[-500:] if r.stderr else "")

# From Contabo host: hit public HTTPS and local service
r2 = subprocess.run(
    ["sh", "-c", """
JWT=$(cat /tmp/sa-jwt.txt)
echo '=== public vault.asrax.in ==='
wget -qO- --header='Content-Type: application/json' \
  --post-data="{\\"role\\":\\"am-backend-role-dev\\",\\"jwt\\":\\"$JWT\\"}" \
  https://vault.asrax.in/v1/auth/jwt-nonprod/login 2>&1 | head -c 800
echo
echo '=== clusterIP via kubectl port-forward quick ==='
"""],
    capture_output=True, text=True, timeout=30,
)
print(r2.stdout)
print(r2.stderr[-400:] if r2.stderr else "")

# What Service is vault?
r3 = subprocess.run(
    ["kubectl", "--kubeconfig", kc, "-n", "vault", "get", "svc,ingress,pods", "-o", "wide"],
    capture_output=True, text=True, timeout=30,
)
print(r3.stdout)
