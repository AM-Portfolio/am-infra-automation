#!/usr/bin/env bash
# Generate Vault root; inject token via shell env inside container (crictl has no -e).
set -euo pipefail
python3 <<'PY'
import json, subprocess, os, shlex
from pathlib import Path

node = "am-prod-infra-worker"
cid = subprocess.check_output(["docker", "exec", node, "crictl", "ps", "--name", "vault", "-q"], text=True).strip().splitlines()[0]
print("cid", cid[:12])

def vexec(args, token=None, stdin=None):
    # Run vault via sh -c so we can set env inside the vault container.
    env_prefix = "VAULT_ADDR=http://127.0.0.1:8200 "
    if token:
        env_prefix += f"VAULT_TOKEN={shlex.quote(token)} "
    inner = env_prefix + "vault " + " ".join(shlex.quote(a) for a in args)
    cmd = ["docker", "exec"]
    if stdin is not None:
        cmd.append("-i")
    cmd += [node, "crictl", "exec"]
    if stdin is not None:
        cmd.append("-i")
    cmd += [cid, "sh", "-c", inner]
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True)

j = json.loads(Path("/data/am-state/vault-prod-infra.json").read_text())
key = (j.get("unseal_keys_b64") or j.get("recovery_keys_b64"))[0]
print(f"key_len={len(key)} prefix={key[:4]}")

vexec(["operator", "generate-root", "-cancel"])
r = vexec(["operator", "generate-root", "-init", "-format=json"])
if r.returncode != 0:
    print("init FAIL", r.stderr or r.stdout)
    raise SystemExit(1)
init = json.loads(r.stdout)
otp, nonce = init["otp"], init["nonce"]
print(f"init ok otp_len={len(otp)} nonce_len={len(nonce)}")

r = vexec(["operator", "generate-root", f"-nonce={nonce}", "-format=json", "-"], stdin=key + "\n")
if r.returncode != 0:
    print("provide FAIL", r.stderr or r.stdout)
    raise SystemExit(1)
prov = json.loads(r.stdout)
print("complete", prov.get("complete"))
encoded = prov["encoded_root_token"]

r = vexec(["operator", "generate-root", f"-decode={encoded}", f"-otp={otp}"])
if r.returncode != 0:
    print("decode FAIL", r.stderr or r.stdout)
    raise SystemExit(1)
token = (r.stdout or "").strip().splitlines()[-1].strip()
print(f"token_prefix={token[:6]} len={len(token)}")

r = vexec(["token", "lookup"], token=token)
print("lookup rc", r.returncode)
if r.returncode != 0:
    print("lookup FAIL", (r.stderr or r.stdout)[:400])
    raise SystemExit(1)
for line in (r.stdout or "").splitlines():
    if line.startswith("display_name") or line.startswith("policies") or line.startswith("path") or line.startswith("type"):
        print(line)

Path("/tmp/am-vault-working.token").write_text(token)
os.chmod("/tmp/am-vault-working.token", 0o600)
j["root_token"] = token
Path("/data/am-state/vault-prod-infra.json").write_text(json.dumps(j, indent=2) + "\n")
envp = Path("/data/am-state/credentials/prod/vault-root.env")
lines = []
replaced = False
if envp.exists():
    for line in envp.read_text().splitlines():
        if line.startswith("VAULT_TOKEN="):
            lines.append(f"VAULT_TOKEN={token}"); replaced = True
        else:
            lines.append(line)
if not replaced:
    lines.append(f"VAULT_TOKEN={token}")
if not any(l.startswith("VAULT_ADDR=") for l in lines):
    lines.insert(0, "VAULT_ADDR=https://vault.asrax.in")
envp.write_text("\n".join(lines) + "\n")
os.chmod(envp, 0o600)
print("UPDATED_SOT_OK")
PY
