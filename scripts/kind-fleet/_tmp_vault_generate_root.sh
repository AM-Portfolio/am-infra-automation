#!/usr/bin/env bash
# Generate a new Vault root token using shamir key from vault-prod-infra.json (Contabo).
# Writes /tmp/am-vault-working.token (0600). Never echoes full token/key.
set -euo pipefail
NODE=am-prod-infra-worker
CID=$(docker exec "$NODE" crictl ps --name vault -q | head -1)
INIT_JSON=/data/am-state/vault-prod-infra.json

python3 <<'PY'
import json, subprocess, os, base64, hashlib
from pathlib import Path

node = "am-prod-infra-worker"
cid = subprocess.check_output(["docker", "exec", node, "crictl", "ps", "--name", "vault", "-q"], text=True).strip().splitlines()[0]
j = json.loads(Path("/data/am-state/vault-prod-infra.json").read_text())
# Prefer unseal_keys_b64[0] for generate-root (shamir threshold 1)
keys = j.get("unseal_keys_b64") or j.get("recovery_keys_b64") or []
if not keys:
    raise SystemExit("no unseal/recovery keys in vault-prod-infra.json")
key = keys[0]
print(f"using key_source={'unseal' if j.get('unseal_keys_b64') else 'recovery'} key_len={len(key)} key_prefix={key[:4]}")

def vex(*args, env=None):
    e = {"VAULT_ADDR": "http://127.0.0.1:8200"}
    if env:
        e.update(env)
    cmd = ["docker", "exec"]
    for k, v in e.items():
        cmd += ["-e", f"{k}={v}"]
    cmd += [node, "crictl", "exec", cid, "vault", *args]
    return subprocess.run(cmd, capture_output=True, text=True)

# cancel any in-progress generate-root
subprocess.run(
    ["docker", "exec", "-e", "VAULT_ADDR=http://127.0.0.1:8200", node, "crictl", "exec", cid, "vault", "operator", "generate-root", "-cancel"],
    capture_output=True, text=True,
)

# init
r = vex("operator", "generate-root", "-init", "-format=json")
if r.returncode != 0:
    print("init FAIL", (r.stderr or r.stdout)[:200])
    raise SystemExit(1)
init = json.loads(r.stdout)
otp = init["otp"]
nonce = init["nonce"]
print(f"generate-root init ok nonce_len={len(nonce)} otp_len={len(otp)}")

# provide unseal key
r = vex("operator", "generate-root", f"-nonce={nonce}", "-format=json", key)
# vault CLI may take key on stdin instead
if r.returncode != 0:
    # try stdin
    cmd = ["docker", "exec", "-i", "-e", "VAULT_ADDR=http://127.0.0.1:8200", node, "crictl", "exec", "-i", cid, "vault", "operator", "generate-root", f"-nonce={nonce}", "-format=json"]
    r = subprocess.run(cmd, input=key + "\n", capture_output=True, text=True)
if r.returncode != 0:
    print("provide key FAIL", (r.stderr or r.stdout)[:300])
    raise SystemExit(1)
prov = json.loads(r.stdout)
print(f"provide ok complete={prov.get('complete')} encoded_root_token_len={len(prov.get('encoded_root_token') or '')}")
if not prov.get("complete"):
    raise SystemExit("generate-root not complete (need more shares?)")

encoded = prov["encoded_root_token"]
# decode with otp
r = vex("operator", "generate-root", f"-decode={encoded}", f"-otp={otp}")
if r.returncode != 0:
    print("decode FAIL", (r.stderr or r.stdout)[:200])
    raise SystemExit(1)
# output is the raw token on last line typically
token = (r.stdout or "").strip().splitlines()[-1].strip()
if not token.startswith("hvs.") and not token.startswith("s."):
    # sometimes json
    try:
        token = json.loads(r.stdout).get("token") or token
    except Exception:
        pass
print(f"new_root prefix={token[:6]} len={len(token)}")

# verify
r = vex("token", "lookup", env={"VAULT_TOKEN": token})
if r.returncode != 0:
    print("lookup FAIL", (r.stderr or r.stdout)[:200])
    raise SystemExit(1)
print("new_root LOOKUP_OK")
Path("/tmp/am-vault-working.token").write_text(token)
os.chmod("/tmp/am-vault-working.token", 0o600)
# update vault-prod-infra.json root_token and vault-root.env (durable SoT)
j["root_token"] = token
Path("/data/am-state/vault-prod-infra.json").write_text(json.dumps(j, indent=2) + "\n")
envp = Path("/data/am-state/credentials/prod/vault-root.env")
lines = []
if envp.exists():
    for line in envp.read_text().splitlines():
        if line.startswith("VAULT_TOKEN="):
            lines.append(f"VAULT_TOKEN={token}")
        else:
            lines.append(line)
    if not any(l.startswith("VAULT_TOKEN=") for l in lines):
        lines.append(f"VAULT_TOKEN={token}")
else:
    lines = [f"VAULT_ADDR=https://vault.asrax.in", f"VAULT_TOKEN={token}"]
envp.write_text("\n".join(lines) + "\n")
os.chmod(envp, 0o600)
print("updated vault-prod-infra.json + credentials/prod/vault-root.env")
PY
