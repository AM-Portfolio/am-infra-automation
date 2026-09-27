#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin

python3 <<'PY'
import json, ssl, urllib.request, subprocess

tok = json.load(open("/data/am-state/vault-dr-infra.json"))["root_token"]
ctx = ssl._create_unverified_context()
addr = "https://vault-dr.asrax.in"
ua = {"User-Agent": "am-kind-fleet-gates/1", "X-Vault-Token": tok}

req = urllib.request.Request(f"{addr}/v1/apps/data/dr/infra/postgres", headers=ua)
with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
    d = json.loads(r.read().decode())
print("postgres_ok", len(((d.get("data") or {}).get("data") or {})))

state = json.loads(
    subprocess.check_output(
        ["terraform", "state", "pull"],
        cwd="/opt/am-infra-automation/terraform/kind-fleet/dr/platform",
    )
)
users = {}
for rsrc in state.get("resources", []):
    if (
        rsrc.get("module") == "module.keycloak"
        and rsrc.get("type") == "random_password"
        and rsrc.get("name") == "test_user"
    ):
        for inst in rsrc.get("instances", []):
            idx = inst.get("index_key")
            result = (inst.get("attributes") or {}).get("result")
            if idx and result:
                users[str(idx)] = result
print("users", sorted(users))
if "am-admin-test" not in users:
    raise SystemExit("missing am-admin-test in TF state")

secret = dict(users)
secret.update(
    {
        "admin_username": "am-admin-test",
        "admin_password": users["am-admin-test"],
        "AM_ADMIN_TEST_USERNAME": "am-admin-test",
        "AM_ADMIN_TEST_PASSWORD": users["am-admin-test"],
    }
)
if "am-user-test" in users:
    secret.update(
        {
            "user_username": "am-user-test",
            "user_password": users["am-user-test"],
            "AM_USER_TEST_USERNAME": "am-user-test",
            "AM_USER_TEST_PASSWORD": users["am-user-test"],
        }
    )

body = json.dumps({"data": secret}).encode()
headers = {
    "User-Agent": "am-kind-fleet-gates/1",
    "X-Vault-Token": tok,
    "Content-Type": "application/json",
}
req = urllib.request.Request(
    f"{addr}/v1/apps/data/dr/infra/keycloak-test-users",
    data=body,
    method="POST",
    headers=headers,
)
with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
    print("write", r.status)

req = urllib.request.Request(f"{addr}/v1/apps/data/dr/infra/keycloak-test-users", headers=ua)
with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
    d = json.loads(r.read().decode())
print("read_keys", sorted(((d.get("data") or {}).get("data") or {}).keys()))
PY

cd /opt/am-infra-automation
PYTHONPATH=scripts/kind-fleet python3 -m phase_gates --env dr --wave 4d 2>&1 | tee /tmp/dr-gate4d.log | tail -60
