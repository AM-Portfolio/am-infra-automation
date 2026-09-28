#!/usr/bin/env python3
"""Canary jwt-nonprod login via vault-0 with laptop SA JWT."""
import json, pathlib, subprocess, sys

tok = pathlib.Path("/tmp/am-vault-root.token").read_text().strip()
jwt = pathlib.Path("/tmp/sa-jwt.txt").read_text().strip()
kc = "/root/.kube/config"
payload = json.dumps({"role": "am-backend-role-dev", "jwt": jwt})
pathlib.Path("/tmp/login.json").write_text(payload)
subprocess.check_call(
    ["kubectl", "--kubeconfig", kc, "-n", "vault", "cp", "/tmp/login.json", "vault-0:/tmp/login.json"]
)

def kexec(script):
    return subprocess.run(
        ["kubectl", "--kubeconfig", kc, "-n", "vault", "exec", "vault-0", "--", "sh", "-c", script],
        capture_output=True, text=True, timeout=60,
    )

for mount in ("jwt-nonprod", "jwt-laptop-apps"):
    r = kexec(
        f"""
curl -sS -w '\\nHTTP:%{{http_code}}\\n' -H 'Content-Type: application/json' \
  --data @/tmp/login.json http://127.0.0.1:8200/v1/auth/{mount}/login
"""
    )
    print(f"=== {mount} ===")
    print((r.stdout or "")[:1500])
    print((r.stderr or "")[:400])

# compare stored pubkey vs regenerating from... we can't. Just show config length
r = kexec(
    f"export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='{tok}'; "
    "vault read -format=json auth/jwt-nonprod/config"
)
data = json.loads(r.stdout or "{}")
pubs = (data.get("data") or {}).get("jwt_validation_pubkeys") or []
print("pubkeys_count", len(pubs))
if pubs:
    print("pubkey_head", pubs[0][:80].replace("\n", "\\n"))
    print("pubkey_tail", pubs[0][-60:].replace("\n", "\\n"))
