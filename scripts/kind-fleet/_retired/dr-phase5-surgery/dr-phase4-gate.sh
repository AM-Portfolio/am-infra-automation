#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
python3 <<'PY'
import json, subprocess, os
tok = json.load(open("/data/am-state/vault-dr-infra.json"))["root_token"]
env = os.environ.copy()
env["KUBECONFIG"] = "/data/am-state/kubeconfig.am-dr-infra.yaml"
env["PATH"] = "/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin"

def vk(*args):
    cmd = ["kubectl", "-n", "vault", "exec", "vault-0", "--",
           "env", f"VAULT_TOKEN={tok}", "VAULT_ADDR=http://127.0.0.1:8200", "vault", *args]
    return subprocess.check_output(cmd, env=env, text=True)

keys = json.loads(vk("kv", "list", "-format=json", "apps/dr/services/"))
# vault kv list -format=json may be a list or {"data":{"keys":[...]}}
if isinstance(keys, list):
    svc = keys
elif isinstance(keys, dict) and "data" in keys:
    d = keys["data"]
    svc = d.get("keys") if isinstance(d, dict) else d
else:
    svc = []
print(f"services={len(svc)}")
ident = json.loads(vk("kv", "get", "-format=json", "-mount=apps", "dr/services/am-identity"))
data = ident["data"]["data"]
print("OIDC_ISSUER=", data.get("OIDC_ISSUER"))
print("hosts_ok=", "auth-dr.asrax.in" in str(data.get("OIDC_ISSUER", "")))
PY
cd /opt/am-infra-automation
PYTHONPATH=scripts/kind-fleet python3 -m phase_gates --env dr --wave 4a
echo PHASE4_GATE_OK
