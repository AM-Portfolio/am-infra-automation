#!/usr/bin/env python3
"""Configure am-realm, roles, and G24 OIDC clients via Keycloak Admin API."""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


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
        with urllib.request.urlopen(request, timeout=30) as resp:
            raw = resp.read()
            if not raw:
                return None
            return json.loads(raw.decode())
    except urllib.error.HTTPError as e:
        err = e.read().decode(errors="replace")
        raise RuntimeError("%s %s -> %s: %s" % (method, url, e.code, err))


def main() -> int:
    base = os.environ["KC_BASE"].rstrip("/")
    admin = os.environ["KC_ADMIN"]
    password = os.environ["KC_PASSWORD"]
    realm = os.environ["REALM"]
    mfa = os.environ.get("MFA_ENFORCE", "false") == "true"
    otp_optional = os.environ.get("OTP_OPTIONAL", "true") == "true"
    roles = json.loads(os.environ["ROLES_JSON"])
    clients = json.loads(os.environ["CLIENTS_JSON"])

    tok = None
    for _ in range(60):
        try:
            tok = req(
                "POST",
                f"{base}/realms/master/protocol/openid-connect/token",
                form={
                    "grant_type": "password",
                    "client_id": "admin-cli",
                    "username": admin,
                    "password": password,
                },
            )
            break
        except Exception:
            time.sleep(5)
    if not tok or "access_token" not in tok:
        print("Keycloak admin token failed", file=sys.stderr)
        return 1

    h = {"Authorization": f"Bearer {tok['access_token']}", "Content-Type": "application/json"}

    try:
        req("GET", f"{base}/admin/realms/{realm}", headers=h)
    except Exception:
        body = json.dumps(
            {"realm": realm, "enabled": True, "displayName": "AM Realm", "sslRequired": "external"}
        ).encode()
        req("POST", f"{base}/admin/realms", headers=h, data=body)

    for role in roles:
        try:
            req("GET", f"{base}/admin/realms/{realm}/roles/{role}", headers=h)
        except Exception:
            req("POST", f"{base}/admin/realms/{realm}/roles", headers=h, data=json.dumps({"name": role}).encode())

    try:
        ra = req("GET", f"{base}/admin/realms/{realm}/authentication/required-actions/CONFIGURE_TOTP", headers=h)
        ra["enabled"] = otp_optional or mfa
        ra["defaultAction"] = mfa
        req(
            "PUT",
            f"{base}/admin/realms/{realm}/authentication/required-actions/CONFIGURE_TOTP",
            headers=h,
            data=json.dumps(ra).encode(),
        )
    except Exception as e:
        print(f"configure_totp_skipped: {e}")

    if mfa:
        try:
            r = req("GET", f"{base}/admin/realms/{realm}", headers=h)
            r["otpPolicyType"] = "totp"
            r["otpPolicyAlgorithm"] = "HmacSHA1"
            r["otpPolicyDigits"] = 6
            r["otpPolicyPeriod"] = 30
            req("PUT", f"{base}/admin/realms/{realm}", headers=h, data=json.dumps(r).encode())
        except Exception as e:
            print(f"mfa_policy_skipped: {e}")

    direct_grants = not mfa
    for c in clients:
        existing = req("GET", f"{base}/admin/realms/{realm}/clients?clientId={urllib.parse.quote(c['clientId'])}", headers=h) or []
        payload = {
            "clientId": c["clientId"],
            "enabled": True,
            "protocol": "openid-connect",
            "publicClient": False,
            "secret": c["secret"],
            "redirectUris": c["redirectUris"],
            "webOrigins": c["webOrigins"],
            "standardFlowEnabled": True,
            "directAccessGrantsEnabled": direct_grants,
            "attributes": {"post.logout.redirect.uris": "##".join(c["redirectUris"])},
        }
        body = json.dumps(payload).encode()
        if existing:
            cid = existing[0]["id"]
            req("PUT", f"{base}/admin/realms/{realm}/clients/{cid}", headers=h, data=body)
        else:
            req("POST", f"{base}/admin/realms/{realm}/clients", headers=h, data=body)

    print(f"realm_ok={realm} clients={len(clients)} mfa_enforce={str(mfa).lower()} direct_grants={direct_grants}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
