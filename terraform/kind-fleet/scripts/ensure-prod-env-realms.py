#!/usr/bin/env python3
"""Create per-env realms on Contabo prod Keycloak (auth.asrax.in). No dig/preprod KC pods.

Realms: am-dev-realm, am-preprod-realm, am-dr-realm
Each gets confidential client am-identity-service (+ am-mcp-service) and demo user.
Prints JSON secrets to stdout for Vault seeding.
"""
from __future__ import annotations

import json
import os
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("KC_BASE", "https://auth.asrax.in").rstrip("/")
ADMIN = os.environ.get("KC_ADMIN", "admin")
PASSWORD = os.environ["KC_PASSWORD"]

REALMS = {
    "am-dev-realm": {
        "ui": "https://am-dev.asrax.in",
        "redirects": [
            "https://am-dev.asrax.in/*",
            "http://localhost:9000/*",
            "http://127.0.0.1:9000/*",
            "http://localhost:9000/callback",
            "http://127.0.0.1:9000/callback",
            "http://localhost:9000/oauth_callback.html",
            "http://127.0.0.1:9000/oauth_callback.html",
        ],
    },
    "am-preprod-realm": {
        "ui": "https://am-preprod.asrax.in",
        "redirects": [
            "https://am-preprod.asrax.in/*",
            "http://localhost:9000/*",
            "http://127.0.0.1:9000/*",
        ],
    },
    "am-dr-realm": {
        "ui": "https://am-dr.asrax.in",
        "redirects": [
            "https://am-dr.asrax.in/*",
            "https://am.asrax.in/*",
            "http://localhost:9000/*",
            "http://127.0.0.1:9000/*",
        ],
    },
}

ROLES = ["am-admin", "am-ops", "am-viewer", "am-user"]
DEMO_EMAIL = os.environ.get("DEMO_EMAIL", "munish.prime@gmail.com")
DEMO_PASSWORD = os.environ.get("DEMO_PASSWORD", "@M1unish")


def req(method, url, headers=None, data=None, form=None):
    h = dict(headers or {})
    body = data
    if form is not None:
        body = urllib.parse.urlencode(form).encode()
        h["Content-Type"] = "application/x-www-form-urlencoded"
    elif body is not None and "Content-Type" not in h:
        h["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=body, headers=h, method=method)
    try:
        with urllib.request.urlopen(request, timeout=60) as resp:
            raw = resp.read()
            if not raw:
                return None, resp.status
            return json.loads(raw.decode()), resp.status
    except urllib.error.HTTPError as e:
        err = e.read().decode(errors="replace")
        if e.code in (404, 409):
            return None, e.code
        raise RuntimeError("%s %s -> %s: %s" % (method, url, e.code, err))


def admin_headers():
    tok, _ = req(
        "POST",
        f"{BASE}/realms/master/protocol/openid-connect/token",
        form={
            "grant_type": "password",
            "client_id": "admin-cli",
            "username": ADMIN,
            "password": PASSWORD,
        },
    )
    if not tok or "access_token" not in tok:
        raise RuntimeError("admin token failed")
    return {
        "Authorization": "Bearer %s" % tok["access_token"],
        "Content-Type": "application/json",
    }


def ensure_realm(h, realm):
    _, code = req("GET", f"{BASE}/admin/realms/{realm}", headers=h)
    if code == 200:
        return
    body = json.dumps(
        {
            "realm": realm,
            "enabled": True,
            "displayName": realm,
            "sslRequired": "external",
            "registrationAllowed": False,
            "loginWithEmailAllowed": True,
            "duplicateEmailsAllowed": False,
            "resetPasswordAllowed": True,
            "editUsernameAllowed": False,
            "ssoSessionIdleTimeout": 86400,
            "ssoSessionMaxLifespan": 86400,
            "accessTokenLifespan": 3600,
            "directGrantFlow": "direct grant",
        }
    ).encode()
    req("POST", f"{BASE}/admin/realms", headers=h, data=body)


def ensure_roles(h, realm):
    for role in ROLES:
        _, code = req("GET", f"{BASE}/admin/realms/{realm}/roles/{role}", headers=h)
        if code == 404:
            req(
                "POST",
                f"{BASE}/admin/realms/{realm}/roles",
                headers=h,
                data=json.dumps({"name": role}).encode(),
            )


def ensure_client(h, realm, client_id, secret, redirects):
    existing, _ = req(
        "GET",
        f"{BASE}/admin/realms/{realm}/clients?clientId={urllib.parse.quote(client_id)}",
        headers=h,
    )
    payload = {
        "clientId": client_id,
        "enabled": True,
        "protocol": "openid-connect",
        "publicClient": False,
        "secret": secret,
        "redirectUris": redirects,
        "webOrigins": ["*"],
        "standardFlowEnabled": True,
        "directAccessGrantsEnabled": True,
        "serviceAccountsEnabled": True,
        "fullScopeAllowed": True,
    }
    if existing:
        cid = existing[0]["id"]
        payload["id"] = cid
        # Keep existing secret when present so Vault re-seeds stay stable.
        sec, _ = req(
            "GET",
            f"{BASE}/admin/realms/{realm}/clients/{cid}/client-secret",
            headers=h,
        )
        live = (sec or {}).get("value") or secret
        payload["secret"] = live
        merged = {**existing[0], **payload}
        req(
            "PUT",
            f"{BASE}/admin/realms/{realm}/clients/{cid}",
            headers=h,
            data=json.dumps(merged).encode(),
        )
        return live
    req(
        "POST",
        f"{BASE}/admin/realms/{realm}/clients",
        headers=h,
        data=json.dumps(payload).encode(),
    )
    return secret


def ensure_user(h, realm, email, password):
    users, _ = req(
        "GET",
        f"{BASE}/admin/realms/{realm}/users?email={urllib.parse.quote(email)}&exact=true",
        headers=h,
    )
    if users:
        uid = users[0]["id"]
    else:
        req(
            "POST",
            f"{BASE}/admin/realms/{realm}/users",
            headers=h,
            data=json.dumps(
                {
                    "username": email,
                    "email": email,
                    "enabled": True,
                    "emailVerified": True,
                    "firstName": "Demo",
                    "lastName": "User",
                }
            ).encode(),
        )
        users, _ = req(
            "GET",
            f"{BASE}/admin/realms/{realm}/users?email={urllib.parse.quote(email)}&exact=true",
            headers=h,
        )
        uid = users[0]["id"]
    req(
        "PUT",
        f"{BASE}/admin/realms/{realm}/users/{uid}/reset-password",
        headers=h,
        data=json.dumps(
            {"type": "password", "value": password, "temporary": False}
        ).encode(),
    )
    # assign am-admin + am-user
    avail, _ = req(
        "GET",
        f"{BASE}/admin/realms/{realm}/users/{uid}/role-mappings/realm/available",
        headers=h,
    )
    want = {r for r in ("am-admin", "am-user", "am-ops") }
    to_add = [r for r in (avail or []) if r.get("name") in want]
    if to_add:
        req(
            "POST",
            f"{BASE}/admin/realms/{realm}/users/{uid}/role-mappings/realm",
            headers=h,
            data=json.dumps(to_add).encode(),
        )


def main() -> int:
    h = admin_headers()
    out = {}
    for realm, cfg in REALMS.items():
        print(f"ensure {realm}", file=sys.stderr)
        ensure_realm(h, realm)
        h = admin_headers()  # refresh
        ensure_roles(h, realm)
        id_secret = secrets.token_urlsafe(24)
        mcp_secret = secrets.token_urlsafe(24)
        id_secret = ensure_client(
            h, realm, "am-identity-service", id_secret, cfg["redirects"]
        )
        mcp_secret = ensure_client(
            h,
            realm,
            "am-mcp-service",
            mcp_secret,
            cfg["redirects"],
        )
        ensure_user(h, realm, DEMO_EMAIL, DEMO_PASSWORD)
        # discovery check
        disc, code = req(
            "GET",
            f"{BASE}/realms/{realm}/.well-known/openid-configuration",
        )
        if code != 200 or not disc:
            raise RuntimeError(f"discovery failed for {realm}: {code}")
        out[realm] = {
            "KEYCLOAK_URL": BASE,
            "KEYCLOAK_REALM": realm,
            "OIDC_ISSUER": f"{BASE}/realms/{realm}",
            "OIDC_DISCOVERY_URL": f"{BASE}/realms/{realm}/.well-known/openid-configuration",
            "OIDC_JWKS_URL": f"{BASE}/realms/{realm}/protocol/openid-connect/certs",
            "OIDC_TOKEN_URL": f"{BASE}/realms/{realm}/protocol/openid-connect/token",
            "AM_IDENTITY_CLIENT_ID": "am-identity-service",
            "AM_IDENTITY_CLIENT_SECRET": id_secret,
            "AM_MCP_CLIENT_ID": "am-mcp-service",
            "AM_MCP_CLIENT_SECRET": mcp_secret,
            "AUTH_UI_BASE_URL": cfg["ui"],
        }
        print(f"ok {realm} discovery={disc.get('issuer')}", file=sys.stderr)
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        raise SystemExit(1)
