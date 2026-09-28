#!/usr/bin/env python3
"""Extract OIDC (random_password.oidc_secret) + test users + argo into env files."""
import base64
import json
import os
import subprocess
import sys
from pathlib import Path

env = sys.argv[1] if len(sys.argv) > 1 else "prod"
state_path = Path(f"/data/am-state/terraform/{env}/platform/terraform.tfstate")
out_dir = Path(f"/data/am-state/credentials/{env}")
out_dir.mkdir(parents=True, exist_ok=True)
os.chmod(out_dir, 0o700)

if env == "prod":
    issuer = "https://auth.asrax.in/realms/am-realm"
    argo_host = "https://argocd.asrax.in"
    auth_host = "auth.asrax.in"
else:
    issuer = "https://auth-dr.asrax.in/realms/am-realm"
    argo_host = "https://argocd-dr.asrax.in"
    auth_host = "auth-dr.asrax.in"

state = json.loads(state_path.read_text(encoding="utf-8"))
oidc = {}
tests = {}
argo_pw = None
kc_pw = None
kc_user = "admin"

for r in state.get("resources") or []:
    mod = r.get("module") or ""
    rtype = r.get("type") or ""
    name = r.get("name") or ""
    for inst in r.get("instances") or []:
        attrs = inst.get("attributes") or {}
        idx = inst.get("index_key")
        result = attrs.get("result")

        if rtype == "random_password" and name == "oidc_secret" and idx and result:
            oidc[str(idx)] = str(result)

        if rtype == "random_password" and name in ("test_admin", "test_user", "am-admin-test", "am-user-test") and result:
            key = str(idx or name)
            tests[key] = str(result)

        if "module.keycloak" in mod and rtype == "random_password" and name == "admin" and result:
            kc_pw = str(result)

        if "module.keycloak" in mod and rtype == "random_password" and "test" in name and result:
            # test_users.tf naming
            if idx:
                tests[str(idx)] = str(result)
            else:
                tests[name] = str(result)

for name, out in (state.get("outputs") or {}).items():
    val = out.get("value")
    if name == "argocd_admin_password" and val:
        argo_pw = val
    if name == "argocd_host" and val:
        host = str(val)
        if host.startswith("https://"):
            host = host[len("https://") :]
        elif host.startswith("http://"):
            host = host[len("http://") :]
        argo_host = f"https://{host}"
    if name == "keycloak_admin_password" and val:
        kc_pw = val
    if name == "issuer_url" and val:
        issuer = val
    if name == "auth_host" and val:
        auth_host = val
        if not issuer.endswith("/realms/am-realm"):
            issuer = f"https://{auth_host}/realms/am-realm"

# Map test_admin/test_user to am-*-test if needed
if "test_admin" in tests and "am-admin-test" not in tests:
    tests["am-admin-test"] = tests["test_admin"]
if "test_user" in tests and "am-user-test" not in tests:
    tests["am-user-test"] = tests["test_user"]

print("oidc_count", len(oidc))
print("oidc_clients", ",".join(sorted(oidc.keys())))
print("test_user_keys", ",".join(sorted(tests.keys())))
print("has_argo_pw", bool(argo_pw))
print("has_kc_pw", bool(kc_pw))

lines = [f"# OIDC clients for {env} (from TF state). Not for git.", f"ISSUER_URL={issuer}"]
for name, secret in sorted(oidc.items()):
    safe = name.upper().replace("-", "_").replace(".", "_")
    lines.append(f"OIDC_{safe}_CLIENT_ID={name}")
    lines.append(f"OIDC_{safe}_CLIENT_SECRET={secret}")
# kubectl is public client
lines.append("OIDC_KUBECTL_CLIENT_ID=kubectl")
lines.append("OIDC_KUBECTL_PUBLIC_CLIENT=true")
(out_dir / "oidc.env").write_text("\n".join(lines) + "\n", encoding="utf-8")
os.chmod(out_dir / "oidc.env", 0o600)
print("wrote oidc.env lines", len(lines))

if tests:
    sso = [f"# SSO test users for {env}. Not for git."]
    for k, v in sorted(tests.items()):
        sso.append(f"{k}={v}")
    if "am-admin-test" in tests:
        sso += [
            "AM_ADMIN_TEST_USERNAME=am-admin-test",
            f"AM_ADMIN_TEST_PASSWORD={tests['am-admin-test']}",
        ]
    if "am-user-test" in tests:
        sso += [
            "AM_USER_TEST_USERNAME=am-user-test",
            f"AM_USER_TEST_PASSWORD={tests['am-user-test']}",
        ]
    (out_dir / "sso-test-users.env").write_text("\n".join(sso) + "\n", encoding="utf-8")
    os.chmod(out_dir / "sso-test-users.env", 0o600)
    print("wrote sso-test-users.env")

if kc_pw:
    kc_lines = [
        f"KEYCLOAK_ADMIN_USER={kc_user}",
        f"KEYCLOAK_ADMIN_PASSWORD={kc_pw}",
        "KEYCLOAK_REALM=am-realm",
        f"KEYCLOAK_URL=https://{auth_host}",
        f"ISSUER_URL={issuer}",
        f"FLEET_ENV={env}",
    ]
    (out_dir / "keycloak-admin.env").write_text("\n".join(kc_lines) + "\n", encoding="utf-8")
    os.chmod(out_dir / "keycloak-admin.env", 0o600)
    compat = Path(f"/data/am-state/credentials/{env}-keycloak-admin.env")
    if compat.exists() or True:
        if compat.is_symlink() or not compat.exists():
            if compat.exists() or compat.is_symlink():
                compat.unlink()
            compat.symlink_to(out_dir / "keycloak-admin.env")
    print("wrote keycloak-admin.env")

if not argo_pw:
    kc_path = f"/data/am-state/kubeconfig.am-{env}-infra.yaml"
    try:
        b64 = subprocess.check_output(
            [
                "kubectl",
                "--kubeconfig",
                kc_path,
                "-n",
                "argocd",
                "get",
                "secret",
                "argocd-secret",
                "-o",
                "jsonpath={.data.admin\\.password}",
            ],
            text=True,
        ).strip()
        if b64:
            argo_pw = base64.b64decode(b64).decode()
    except Exception as e:
        print("argo_k8s_err", type(e).__name__)

if argo_pw:
    (out_dir / "argocd-admin.env").write_text(
        "\n".join(
            [
                "ARGOCD_ADMIN_USER=admin",
                f"ARGOCD_ADMIN_PASSWORD={argo_pw}",
                f"ARGOCD_HOST={argo_host}",
                f"FLEET_ENV={env}",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    os.chmod(out_dir / "argocd-admin.env", 0o600)
    print("wrote argocd-admin.env")

# Try write OIDC to Vault (best-effort; root may be 403 on apps/)
keys_path = Path(f"/data/am-state/vault-{env}-infra.json")
vault_addr = "https://vault.asrax.in" if env == "prod" else f"https://vault-{env}.asrax.in"
vault_ok = 0
vault_err = None
if keys_path.exists() and oidc:
    import urllib.error
    import urllib.request

    token = json.loads(keys_path.read_text(encoding="utf-8-sig")).get("root_token") or ""
    for name, secret in oidc.items():
        path = f"apps/data/{env}/oidc/{name}"
        body = json.dumps(
            {"data": {"client_id": name, "client_secret": secret, "issuer_url": issuer}}
        ).encode()
        req = urllib.request.Request(
            f"{vault_addr}/v1/{path}",
            data=body,
            method="POST",
            headers={"X-Vault-Token": token, "Content-Type": "application/json"},
        )
        try:
            urllib.request.urlopen(req, timeout=20)
            vault_ok += 1
        except Exception as e:
            vault_err = getattr(e, "code", type(e).__name__)
            break
    if tests:
        path = f"apps/data/{env}/infra/keycloak-test-users"
        secret_map = dict(tests)
        body = json.dumps({"data": secret_map}).encode()
        req = urllib.request.Request(
            f"{vault_addr}/v1/{path}",
            data=body,
            method="POST",
            headers={"X-Vault-Token": token, "Content-Type": "application/json"},
        )
        try:
            urllib.request.urlopen(req, timeout=20)
            print("vault_test_users_ok")
        except Exception as e:
            print("vault_test_users_err", getattr(e, "code", type(e).__name__))

print("vault_oidc_written", vault_ok, "err", vault_err)
print("done", env)
