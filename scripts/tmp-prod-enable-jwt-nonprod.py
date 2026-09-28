#!/usr/bin/env python3
"""On prod VPS: ensure jwt-nonprod + laptop JWKS; optionally list apps/data/dev."""
import json, pathlib, subprocess, sys, urllib.request

tok = json.loads(pathlib.Path("/data/am-state/vault-prod-infra.json").read_text())["root_token"]
cfg = pathlib.Path("/tmp/jwt-nonprod.json")
role = pathlib.Path("/tmp/jwt-nonprod-role.json")
if not cfg.exists():
    print("MISSING", cfg)
    sys.exit(2)

# Prefer in-cluster vault via kubeconfig if API works; else https://vault.asrax.in; else localhost NodePort
addrs = []
for a in (
    "http://127.0.0.1:8200",
    "https://vault.asrax.in",
    "http://vault.vault.svc.cluster.local:8200",
):
    addrs.append(a)

# try health to pick working addr matching this root
chosen = None
for a in addrs:
    try:
        req = urllib.request.Request(
            a.rstrip("/") + "/v1/auth/token/lookup-self",
            headers={"X-Vault-Token": tok},
        )
        with urllib.request.urlopen(req, timeout=15) as r:
            d = json.loads(r.read().decode())
            print("ADDR_OK", a, "policies", (d.get("data") or {}).get("policies"))
            chosen = a
            break
    except Exception as e:
        print("ADDR_FAIL", a, getattr(e, "code", None), type(e).__name__)

if not chosen:
    # try kubectl exec vault-0
    print("falling back to kubectl exec")
    kc = "/data/am-state/kubeconfig.am-prod-infra.yaml"
    subprocess.check_call(
        ["kubectl", "--kubeconfig", kc, "-n", "vault", "cp", str(cfg), "vault-0:/tmp/jwt-nonprod.json"]
    )
    if role.exists():
        subprocess.check_call(
            ["kubectl", "--kubeconfig", kc, "-n", "vault", "cp", str(role), "vault-0:/tmp/jwt-nonprod-role.json"]
        )
    script = f"""
set -e
export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='{tok}'
vault auth list || true
vault auth enable -path=jwt-nonprod jwt 2>/dev/null || true
if command -v wget >/dev/null; then
  wget -qO- --header="X-Vault-Token: $VAULT_TOKEN" --header="Content-Type: application/json" --post-file=/tmp/jwt-nonprod.json http://127.0.0.1:8200/v1/auth/jwt-nonprod/config
else
  vault write auth/jwt-nonprod/config @"/tmp/jwt-nonprod.json"
fi
echo
vault read auth/jwt-nonprod/config | head -20
if [ -f /tmp/jwt-nonprod-role.json ]; then
  wget -qO- --header="X-Vault-Token: $VAULT_TOKEN" --header="Content-Type: application/json" --post-file=/tmp/jwt-nonprod-role.json http://127.0.0.1:8200/v1/auth/jwt-nonprod/role/am-backend-role-dev || true
  echo
  vault policy write am-backend-policy-dev - <<'EOF'
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
  vault read auth/jwt-nonprod/role/am-backend-role-dev | head -25
fi
vault secrets list | head
"""
    r = subprocess.run(
        ["kubectl", "--kubeconfig", kc, "-n", "vault", "exec", "vault-0", "--", "sh", "-c", script],
        capture_output=True,
        text=True,
        timeout=180,
    )
    print(r.stdout[-3000:])
    print(r.stderr[-800:])
    sys.exit(r.returncode)

addr = chosen


def call(method, path, data=None):
    headers = {"X-Vault-Token": tok}
    body = None
    if data is not None:
        headers["Content-Type"] = "application/json"
        body = json.dumps(data).encode()
    req = urllib.request.Request(addr.rstrip("/") + path, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=60) as r:
        raw = r.read()
        return json.loads(raw.decode()) if raw else {}


# enable jwt-nonprod
try:
    call("POST", "/v1/sys/auth/jwt-nonprod", {"type": "jwt", "description": "dig laptop Kind JWT"})
    print("enabled jwt-nonprod")
except Exception as e:
    print("enable note", getattr(e, "code", None), e)

payload = json.loads(cfg.read_text())
call("POST", "/v1/auth/jwt-nonprod/config", payload)
print("config written")
print(call("GET", "/v1/auth/jwt-nonprod/config"))

if role.exists():
    # policy
    policy = """
path \"apps/data/dev/*\" {
  capabilities = [\"read\"]
}
path \"apps/data/dev\" {
  capabilities = [\"list\"]
}
path \"apps/metadata/dev/*\" {
  capabilities = [\"list\", \"read\"]
}
"""
    call("PUT", "/v1/sys/policy/am-backend-policy-dev", {"policy": policy})
    call("POST", "/v1/auth/jwt-nonprod/role/am-backend-role-dev", json.loads(role.read_text()))
    print("role written")
    print(call("GET", "/v1/auth/jwt-nonprod/role/am-backend-role-dev"))

# list dev
try:
    d = call("LIST", "/v1/apps/metadata/dev")
    print("dev keys", (d.get("data") or {}).get("keys"))
except Exception as e:
    print("dev list", getattr(e, "code", None), e)
