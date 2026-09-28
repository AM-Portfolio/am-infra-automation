#!/usr/bin/env python3
"""Fix am-realm missing OAuth client scopes groups/roles (invalid_scope for Argo/Vault).

Run on Contabo (prod) or VPS3 (dr):
  python3 scripts/kind-fleet/fix-keycloak-oidc-scopes.py [--env prod]

Uses /data/am-state/credentials/<env>/keycloak-admin.env + oidc.env.
Does not print secrets.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


def load_env(path: str) -> dict:
    out = {}
    with open(path, encoding="utf-8-sig") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def req(method, url, headers=None, data=None, form=None):
    h = dict(headers or {})
    body = data
    if form is not None:
        body = urllib.parse.urlencode(form).encode()
        h["Content-Type"] = "application/x-www-form-urlencoded"
    elif body is not None and "Content-Type" not in h:
        h["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=body, method=method, headers=h)
    try:
        with urllib.request.urlopen(request, timeout=30) as resp:
            raw = resp.read()
            return json.loads(raw.decode()) if raw else None
    except urllib.error.HTTPError as e:
        err = e.read().decode(errors="replace")
        raise RuntimeError("%s %s -> %s: %s" % (method, url, e.code, err[:300]))


def ensure_scope(h, base, realm, name, claim):
    scopes = req("GET", f"{base}/admin/realms/{realm}/client-scopes", headers=h) or []
    scope = next((s for s in scopes if s.get("name") == name), None)
    payload = {
        "name": name,
        "protocol": "openid-connect",
        "attributes": {
            "include.in.token.scope": "true",
            "display.on.consent.screen": "false",
        },
        "description": f"AM realm roles as {claim} claim",
    }
    if scope:
        sid = scope["id"]
        merged = dict(scope)
        merged.update(payload)
        merged["id"] = sid
        req(
            "PUT",
            f"{base}/admin/realms/{realm}/client-scopes/{sid}",
            headers=h,
            data=json.dumps(merged).encode(),
        )
    else:
        req(
            "POST",
            f"{base}/admin/realms/{realm}/client-scopes",
            headers=h,
            data=json.dumps(payload).encode(),
        )
        scopes = req("GET", f"{base}/admin/realms/{realm}/client-scopes", headers=h) or []
        scope = next(s for s in scopes if s.get("name") == name)
        sid = scope["id"]

    mapper = {
        "name": f"am-{name}-roles",
        "protocol": "openid-connect",
        "protocolMapper": "oidc-usermodel-realm-role-mapper",
        "consentRequired": False,
        "config": {
            "multivalued": "true",
            "userinfo.token.claim": "true",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "claim.name": claim,
            "jsonType.label": "String",
        },
    }
    existing = (
        req(
            "GET",
            f"{base}/admin/realms/{realm}/client-scopes/{sid}/protocol-mappers/models",
            headers=h,
        )
        or []
    )
    if not any(m.get("name") == mapper["name"] for m in existing):
        req(
            "POST",
            f"{base}/admin/realms/{realm}/client-scopes/{sid}/protocol-mappers/models",
            headers=h,
            data=json.dumps(mapper).encode(),
        )
    return sid


def attach_default(h, base, realm, cid, sid, name):
    defaults = (
        req("GET", f"{base}/admin/realms/{realm}/clients/{cid}/default-client-scopes", headers=h)
        or []
    )
    if any(s.get("id") == sid or s.get("name") == name for s in defaults):
        return "already"
    optionals = (
        req("GET", f"{base}/admin/realms/{realm}/clients/{cid}/optional-client-scopes", headers=h)
        or []
    )
    if any(s.get("id") == sid or s.get("name") == name for s in optionals):
        req(
            "DELETE",
            f"{base}/admin/realms/{realm}/clients/{cid}/optional-client-scopes/{sid}",
            headers=h,
        )
    req(
        "PUT",
        f"{base}/admin/realms/{realm}/clients/{cid}/default-client-scopes/{sid}",
        headers=h,
    )
    return "attached"


def probe_authz(issuer: str, client_id: str, redirect: str, scopes: str) -> str:
    """Hit authorize endpoint; invalid_scope appears in Location or body."""
    q = urllib.parse.urlencode(
        {
            "client_id": client_id,
            "redirect_uri": redirect,
            "response_type": "code",
            "scope": scopes,
            "state": "am-scope-probe",
        }
    )
    # Prefer in-cluster / PF base when issuer is public but CF blocks VPS egress
    auth_base = os.environ.get("KC_AUTH_BASE") or issuer
    url = f"{auth_base.rstrip('/')}/protocol/openid-connect/auth?{q}"
    # Don't follow redirects into CF-blocked public hosts for the error check —
    # Keycloak itself responds 302 to login or to redirect_uri?error=
    opener = urllib.request.build_opener(urllib.request.HTTPRedirectHandler)
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    opener = urllib.request.build_opener(NoRedirect)
    req_obj = urllib.request.Request(url, method="GET")
    try:
        with opener.open(req_obj, timeout=20) as resp:
            loc = resp.headers.get("Location") or ""
            code = resp.status
            body = resp.read().decode(errors="replace")[:300]
    except urllib.error.HTTPError as e:
        loc = e.headers.get("Location") or ""
        code = e.code
        body = e.read().decode(errors="replace")[:300]
    blob = f"{loc}\n{body}"
    if "invalid_scope" in blob or "Invalid+scopes" in blob or "Invalid scopes" in blob:
        return f"FAIL invalid_scope http={code} loc={loc[:180]}"
    if code in (200, 302, 303, 307):
        return f"OK http={code} (no invalid_scope)"
    return f"WARN http={code} loc={loc[:120]} body={body[:80]}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--env", default="prod", choices=["prod", "dr"])
    args = ap.parse_args()
    env = args.env
    cred = f"/data/am-state/credentials/{env}"
    kc = load_env(f"{cred}/keycloak-admin.env")
    oidc = load_env(f"{cred}/oidc.env")

    realm = kc.get("KEYCLOAK_REALM", "am-realm")
    issuer = kc.get("ISSUER_URL") or oidc.get("ISSUER_URL") or (
        "https://auth.asrax.in/realms/am-realm"
        if env == "prod"
        else "https://auth-dr.asrax.in/realms/am-realm"
    )
    # Admin API via in-cluster or public — prefer public auth host from KEYCLOAK_URL
    public = (kc.get("KEYCLOAK_URL") or issuer.split("/realms/")[0]).rstrip("/")
    admin_user = kc["KEYCLOAK_ADMIN_USER"]
    admin_pass = kc["KEYCLOAK_ADMIN_PASSWORD"]

    # Token against public Keycloak (master realm)
    tok = req(
        "POST",
        f"{public}/realms/master/protocol/openid-connect/token",
        form={
            "grant_type": "password",
            "client_id": "admin-cli",
            "username": admin_user,
            "password": admin_pass,
        },
    )
    h = {"Authorization": f"Bearer {tok['access_token']}", "Content-Type": "application/json"}
    base = public

    print(f"env={env} issuer={issuer} admin_api={base}")
    before = [s.get("name") for s in (req("GET", f"{base}/admin/realms/{realm}/client-scopes", headers=h) or [])]
    print("scopes_before", sorted(before))

    gid = ensure_scope(h, base, realm, "groups", "groups")
    rid = ensure_scope(h, base, realm, "roles", "roles")
    print(f"ensured groups={gid} roles={rid}")

    clients = req("GET", f"{base}/admin/realms/{realm}/clients?max=200", headers=h) or []
    attached = 0
    for c in clients:
        cid_name = c.get("clientId") or ""
        if c.get("protocol") != "openid-connect":
            continue
        # skip built-ins
        if cid_name in ("account", "account-console", "admin-cli", "broker", "realm-management", "security-admin-console"):
            continue
        try:
            attach_default(h, base, realm, c["id"], gid, "groups")
            attach_default(h, base, realm, c["id"], rid, "roles")
            attached += 1
        except Exception as e:
            print(f"attach_fail {cid_name}: {e}")
    print(f"clients_updated={attached}")

    after = [s.get("name") for s in (req("GET", f"{base}/admin/realms/{realm}/client-scopes", headers=h) or [])]
    print("scopes_after", sorted(after))
    print("has_groups", "groups" in after, "has_roles", "roles" in after)

    # Probe authorize for key clients
    probes = [
        ("argocd", "https://argocd.asrax.in/auth/callback", "openid profile email groups"),
        ("vault-ui", "https://vault.asrax.in/ui/vault/auth/oidc/oidc/callback", "openid profile email roles groups"),
        ("grafana", "https://grafana.asrax.in/login/generic_oauth", "openid profile email roles groups"),
        ("headlamp", "https://headlamp.asrax.in/oidc-callback", "openid profile email roles groups"),
    ]
    if env == "dr":
        probes = [
            ("argocd", "https://argocd-dr.asrax.in/auth/callback", "openid profile email groups"),
            ("vault-ui", "https://vault-dr.asrax.in/ui/vault/auth/oidc/oidc/callback", "openid profile email roles groups"),
        ]

    print("--- authorize probes ---")
    # When admin API is localhost PF, also probe authorize on same base (avoid CF 1010).
    if base.startswith("http://127.0.0.1") or base.startswith("http://localhost"):
        os.environ["KC_AUTH_BASE"] = f"{base}/realms/{realm}"
    fails = 0
    for client_id, redirect, scopes in probes:
        # only probe if client exists
        if not any(c.get("clientId") == client_id for c in clients):
            print(f"SKIP {client_id} (no client)")
            continue
        result = probe_authz(issuer, client_id, redirect, scopes)
        print(f"{client_id}: {result}")
        if result.startswith("FAIL"):
            fails += 1

    # well-known (prefer PF)
    disc_base = os.environ.get("KC_AUTH_BASE") or issuer
    try:
        wk = req("GET", f"{disc_base}/.well-known/openid-configuration")
        print("discovery_ok issuer=", wk.get("issuer"))
        print("scopes_supported=", wk.get("scopes_supported"))
        if "groups" not in (wk.get("scopes_supported") or []):
            print("WARN discovery missing groups in scopes_supported")
            fails += 1
    except Exception as e:
        print("discovery_err", e)
        fails += 1

    return 1 if fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
