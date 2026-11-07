#!/usr/bin/env bash
# Generate root + verify with env injected INTO vault container (crictl exec -e).
set -euo pipefail
NODE=am-prod-infra-worker
CID=$(docker exec "$NODE" crictl ps --name vault -q | head -1)
echo "cid=${CID:0:12}"

vexec() {
  # usage: vexec [VAULT_TOKEN=...] vault args...
  local tok_env=()
  if [[ "${1:-}" == VAULT_TOKEN=* ]]; then
    tok_env=(-e "$1")
    shift
  fi
  docker exec -e VAULT_ADDR=http://127.0.0.1:8200 "$NODE" \
    crictl exec "${tok_env[@]}" -e VAULT_ADDR=http://127.0.0.1:8200 "$CID" vault "$@"
}

python3 <<'PY'
import json, subprocess, os
from pathlib import Path

node = "am-prod-infra-worker"
cid = subprocess.check_output(["docker", "exec", node, "crictl", "ps", "--name", "vault", "-q"], text=True).strip().splitlines()[0]

def vexec(args, token=None, stdin=None):
    cmd = ["docker", "exec", "-e", "VAULT_ADDR=http://127.0.0.1:8200"]
    if stdin is not None:
        cmd.append("-i")
    cmd += [node, "crictl", "exec"]
    if stdin is not None:
        cmd.append("-i")
    if token:
        cmd += ["-e", f"VAULT_TOKEN={token}"]
    cmd += ["-e", "VAULT_ADDR=http://127.0.0.1:8200", cid, "vault", *args]
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True)

j = json.loads(Path("/data/am-state/vault-prod-infra.json").read_text())
key = (j.get("unseal_keys_b64") or j.get("recovery_keys_b64"))[0]
print(f"key_len={len(key)} prefix={key[:4]}")

# cancel prior
vexec(["operator", "generate-root", "-cancel"])

r = vexec(["operator", "generate-root", "-init", "-format=json"])
print("init rc", r.returncode, (r.stderr or "")[:120])
init = json.loads(r.stdout)
otp, nonce = init["otp"], init["nonce"]
print(f"nonce_len={len(nonce)} otp_len={len(otp)}")

r = vexec(["operator", "generate-root", f"-nonce={nonce}", "-format=json"], stdin=key + "\n")
print("provide rc", r.returncode, (r.stderr or "")[:200])
if r.returncode != 0:
    raise SystemExit(1)
prov = json.loads(r.stdout)
print("complete", prov.get("complete"), "encoded_len", len(prov.get("encoded_root_token") or ""))
encoded = prov["encoded_root_token"]

r = vexec(["operator", "generate-root", f"-decode={encoded}", f"-otp={otp}"])
print("decode rc", r.returncode, "out_lines", len((r.stdout or "").splitlines()), "err", (r.stderr or "")[:120])
token = (r.stdout or "").strip().splitlines()[-1].strip()
print(f"token_prefix={token[:6]} len={len(token)}")

r = vexec(["token", "lookup"], token=token)
print("lookup rc", r.returncode)
if r.returncode != 0:
    print("lookup err", (r.stderr or r.stdout)[:300])
    raise SystemExit(1)
# redact id lines
for line in (r.stdout or "").splitlines():
    if line.lower().startswith("id ") or "token" in line.lower() and "accessor" not in line.lower():
        if line.strip().startswith("id"):
            print("id=***")
            continue
    if any(line.startswith(x) for x in ("display_name", "path", "type", "ttl", "orphan", "meta", "num_uses", "policies")):
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
