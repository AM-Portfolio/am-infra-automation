#!/usr/bin/env python3
"""Probe TF state + Vault mounts (no secret values printed)."""
import json
import urllib.request
import urllib.error
import sys

env = sys.argv[1] if len(sys.argv) > 1 else "prod"
state_path = f"/data/am-state/terraform/{env}/platform/terraform.tfstate"
keys_path = f"/data/am-state/vault-{env}-infra.json"
addr = "https://vault.asrax.in" if env == "prod" else f"https://vault-{env}.asrax.in"

state = json.load(open(state_path))
resources = state.get("resources") or []
print("resource_count", len(resources))

# TF >=0.14 may store under values
vals = state.get("values") or {}
if vals:
    outs = vals.get("outputs") or {}
    print("root_outputs", sorted(outs.keys()))

oidc_clients = []
test_users = []
for r in resources:
    for inst in r.get("instances") or []:
        attrs = inst.get("attributes") or {}
        if isinstance(attrs.get("oidc_client_secrets"), dict):
            oidc_clients = sorted(attrs["oidc_client_secrets"].keys())
            print(
                "oidc_from",
                r.get("module"),
                r.get("type"),
                r.get("name"),
                "count",
                len(oidc_clients),
            )
            print("oidc_clients", ",".join(oidc_clients))
        if isinstance(attrs.get("test_user_passwords"), dict):
            test_users = sorted(attrs["test_user_passwords"].keys())
            print("test_users", ",".join(test_users))

# Also scan sensitive values in child modules via root module resources of type null_resource triggers
# Fallback: terraform show style in values.root_module
root = (vals.get("root_module") or {}) if vals else {}


def walk_module(mod, path="root"):
    for out_name, out in (mod.get("outputs") or {}).items():
        if out_name in ("oidc_client_secrets", "test_user_passwords"):
            v = out.get("value")
            if isinstance(v, dict):
                print(f"module_output {path}.{out_name} count={len(v)} keys={','.join(sorted(v.keys())[:30])}")
    for child in mod.get("child_modules") or []:
        walk_module(child, path + "/" + (child.get("address") or "?"))


if root:
    walk_module(root)

with open(keys_path, encoding="utf-8-sig") as f:
    token = json.load(f).get("root_token") or ""
req = urllib.request.Request(f"{addr}/v1/sys/mounts", headers={"X-Vault-Token": token})
try:
    with urllib.request.urlopen(req, timeout=20) as r:
        mounts = json.loads(r.read().decode())
    names = sorted(k.rstrip("/") for k in mounts.keys() if not k.startswith(("sys/", "identity/", "cubbyhole", "token")))
    print("vault_mounts", ",".join(names[:50]))
except Exception as e:
    print("vault_mounts_err", type(e).__name__, getattr(e, "code", e))

# try common read paths
for path in (
    f"apps/data/{env}/oidc/argocd",
    f"secret/data/{env}/oidc/argocd",
    f"kv/data/{env}/oidc/argocd",
):
    req = urllib.request.Request(f"{addr}/v1/{path}", headers={"X-Vault-Token": token})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            print("vault_read_ok", path)
    except urllib.error.HTTPError as e:
        print("vault_read_err", path, e.code)
