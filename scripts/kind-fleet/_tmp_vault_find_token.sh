#!/usr/bin/env bash
# Inventory Vault token candidates and try them (never print full tokens).
set -euo pipefail
NODE=am-prod-infra-worker
CID=$(docker exec "$NODE" crictl ps --name vault -q | head -1 || true)
if [[ -z "$CID" ]]; then
  NODE=am-prod-infra-control-plane
  CID=$(docker exec "$NODE" crictl ps --name vault -q | head -1 || true)
fi
echo "vault_cid_node=$NODE cid=${CID:0:12}"

try_token() {
  local label="$1" tok="$2"
  local len=${#tok}
  local pref="${tok:0:6}"
  echo -n "TRY $label len=$len prefix=$pref -> "
  if docker exec -e VAULT_TOKEN="$tok" -e VAULT_ADDR=http://127.0.0.1:8200 "$NODE" \
      crictl exec "$CID" vault token lookup >/tmp/am-vault-lookup.out 2>/tmp/am-vault-lookup.err; then
    echo "OK"
    # show non-secret fields only
    grep -E '^(display_name|path|type|ttl|orphan|id)' /tmp/am-vault-lookup.out | head -10 || true
    echo "$tok" > /tmp/am-vault-working.token
    chmod 600 /tmp/am-vault-working.token
    return 0
  fi
  echo "FAIL $(tr '\n' ' ' </tmp/am-vault-lookup.err | head -c 120)"
  return 1
}

# status
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 "$NODE" crictl exec "$CID" vault status 2>&1 | head -15 || true

# candidates from known files
python3 <<'PY'
import json, re
from pathlib import Path

cands = []  # (label, token)

def add(label, tok):
    tok = (tok or "").strip().strip('"').strip("'")
    if tok and len(tok) >= 20:
        cands.append((label, tok))

p = Path("/data/am-state/vault-prod-infra.json")
if p.exists():
    j = json.loads(p.read_text())
    add("vault-prod-infra.json/root_token", j.get("root_token"))
    for k, v in j.items():
        if isinstance(v, str) and ("token" in k.lower() or v.startswith("hvs.") or v.startswith("s.")):
            add(f"vault-prod-infra.json/{k}", v)

for envp in [
    Path("/data/am-state/credentials/prod/vault-root.env"),
    Path("/data/am-state/credentials/credentials.env"),
    Path("/home/am-ops/.asrax/credentials.env"),
    Path("/root/.asrax/credentials.env"),
]:
    if not envp.exists():
        continue
    t = envp.read_text(encoding="utf-8", errors="ignore")
    for m in re.finditer(r"(?m)^(VAULT_TOKEN|VAULT_ROOT_TOKEN|ROOT_TOKEN)=(.*)$", t):
        add(f"{envp}/{m.group(1)}", m.group(2))

# tfstate scan (careful)
for p in Path("/data/am-state/terraform/prod").rglob("*.tfstate"):
    try:
        t = p.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        continue
    for m in re.finditer(r'"(?:root_token|vault_token|token)"\s*:\s*"(hvs\.[^"]+|s\.[^"]+)"', t):
        add(f"tfstate:{p.name}", m.group(1))
    for m in re.finditer(r"\bhvs\.[A-Za-z0-9._-]{16,}\b", t):
        add(f"tfstate-hvs:{p.name}", m.group(0))

# dedupe
seen = set()
out = []
for label, tok in cands:
    if tok in seen:
        continue
    seen.add(tok)
    out.append((label, tok))

Path("/tmp/am-vault-cands.tsv").write_text(
    "\n".join(f"{i}\t{label}\t{len(tok)}\t{tok[:6]}" for i, (label, tok) in enumerate(out)) + "\n"
)
Path("/tmp/am-vault-cands.json").write_text(json.dumps([(l, t) for l, t in out]))
print(f"candidates={len(out)}")
for i, (label, tok) in enumerate(out):
    print(f"  [{i}] {label} len={len(tok)} prefix={tok[:6]}")
PY

python3 <<'PY'
import json, subprocess, os
cands = json.loads(open("/tmp/am-vault-cands.json").read())
node = os.environ.get("NODE", "am-prod-infra-worker")
# get from earlier echo - re-detect
import subprocess as sp
node = "am-prod-infra-worker"
cid = sp.check_output(["docker", "exec", node, "crictl", "ps", "--name", "vault", "-q"], text=True).strip().splitlines()
if not cid:
    node = "am-prod-infra-control-plane"
    cid = sp.check_output(["docker", "exec", node, "crictl", "ps", "--name", "vault", "-q"], text=True).strip().splitlines()
cid = cid[0]
print("using", node, cid[:12])
ok = False
for label, tok in cands:
    env = {**os.environ, "VAULT_TOKEN": tok, "VAULT_ADDR": "http://127.0.0.1:8200"}
    r = sp.run(
        ["docker", "exec", "-e", f"VAULT_TOKEN={tok}", "-e", "VAULT_ADDR=http://127.0.0.1:8200", node, "crictl", "exec", cid, "vault", "token", "lookup"],
        capture_output=True, text=True,
    )
    pref = tok[:6]
    if r.returncode == 0:
        print(f"OK {label} prefix={pref}")
        open("/tmp/am-vault-working.token", "w").write(tok)
        os.chmod("/tmp/am-vault-working.token", 0o600)
        open("/tmp/am-vault-working.label", "w").write(label)
        ok = True
        break
    err = (r.stderr or r.stdout or "").replace("\n", " ")[:100]
    print(f"FAIL {label} prefix={pref} {err}")
print("WORKING=" + ("yes" if ok else "no"))
PY
