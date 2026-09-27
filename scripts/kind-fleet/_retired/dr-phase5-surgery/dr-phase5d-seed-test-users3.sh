#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin

python3 <<'PY'
import json, ssl, urllib.request, subprocess

tok = json.load(open("/data/am-state/vault-dr-infra.json"))["root_token"]
ctx = ssl._create_unverified_context()
addr = "https://vault-dr.asrax.in"

state = json.loads(
    subprocess.check_output(
        ["terraform", "state", "pull"],
        cwd="/opt/am-infra-automation/terraform/kind-fleet/dr/platform",
    )
)

def pw(name: str) -> str:
    for rsrc in state.get("resources", []):
        if (
            rsrc.get("module") == "module.keycloak"
            and rsrc.get("type") == "random_password"
            and rsrc.get("name") == name
        ):
            inst = (rsrc.get("instances") or [None])[0]
            attrs = (inst or {}).get("attributes") or {}
            # result may be sensitive but present in state pull
            if "result" in attrs and attrs["result"]:
                return attrs["result"]
            print("attrs for", name, sorted(attrs.keys()))
    raise SystemExit(f"missing password {name}")

admin_pw = pw("test_admin")
user_pw = pw("test_user")
print("got passwords lens", len(admin_pw), len(user_pw))

secret = {
    "am-admin-test": admin_pw,
    "am-user-test": user_pw,
    "admin_username": "am-admin-test",
    "admin_password": admin_pw,
    "AM_ADMIN_TEST_USERNAME": "am-admin-test",
    "AM_ADMIN_TEST_PASSWORD": admin_pw,
    "user_username": "am-user-test",
    "user_password": user_pw,
    "AM_USER_TEST_USERNAME": "am-user-test",
    "AM_USER_TEST_PASSWORD": user_pw,
}
body = json.dumps({"data": secret}).encode()
req = urllib.request.Request(
    f"{addr}/v1/apps/data/dr/infra/keycloak-test-users",
    data=body,
    method="POST",
    headers={
        "X-Vault-Token": tok,
        "Content-Type": "application/json",
        "User-Agent": "am-kind-fleet-gates/1",
    },
)
with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
    print("write", r.status)

req = urllib.request.Request(
    f"{addr}/v1/apps/data/dr/infra/keycloak-test-users",
    headers={"X-Vault-Token": tok, "User-Agent": "am-kind-fleet-gates/1"},
)
with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
    d = json.loads(r.read().decode())
print("read_keys", sorted(((d.get("data") or {}).get("data") or {}).keys()))
PY

cd /opt/am-infra-automation
PYTHONPATH=scripts/kind-fleet python3 -m phase_gates --env dr --wave 4d 2>&1 | tee /tmp/dr-gate4d.log | tail -80
