#!/usr/bin/env python3
"""Verify Vault OIDC presence without printing secrets."""
import json
import sys
import urllib.error
import urllib.request

env = sys.argv[1] if len(sys.argv) > 1 else "prod"
if env == "prod":
    addr = "https://vault.asrax.in"
    keys_path = "/data/am-state/vault-prod-infra.json"
elif env == "dr":
    addr = "https://vault-dr.asrax.in"
    keys_path = "/data/am-state/vault-dr-infra.json"
else:
    print("usage: verify-env-credentials.py prod|dr")
    sys.exit(2)

with open(keys_path, encoding="utf-8-sig") as f:
    token = json.load(f).get("root_token") or ""


def call(method, path):
    req = urllib.request.Request(
        f"{addr}/v1/{path}",
        method=method,
        headers={"X-Vault-Token": token},
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return {"error": e.code}


listed = call("LIST", f"apps/metadata/{env}/oidc")
if "error" in listed:
    print(f"vault_oidc_list_err {listed['error']}")
    keys = []
else:
    keys = list((listed.get("data") or {}).get("keys") or [])
    print(f"vault_oidc_count {len(keys)}")
    print("vault_oidc_sample " + ",".join(keys[:12]))

ok = 0
for name in keys[:30]:
    name = name.rstrip("/")
    r = call("GET", f"apps/data/{env}/oidc/{name}")
    if "error" in r:
        print(f"vault_get_err {name} {r['error']}")
        continue
    data = (r.get("data") or {}).get("data") or {}
    if data.get("client_secret"):
        ok += 1
print(f"vault_oidc_with_secret {ok}")

tu = call("GET", f"apps/data/{env}/infra/keycloak-test-users")
if "error" in tu:
    print(f"vault_test_users_err {tu['error']}")
else:
    data = (tu.get("data") or {}).get("data") or {}
    print(f"vault_test_users_keys {sorted(data.keys())}")
