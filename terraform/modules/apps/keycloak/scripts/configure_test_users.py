#!/usr/bin/env python3
"""Upsert am-admin-test / am-user-test personas in am-realm."""
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


def ensure_user(base, h, realm, username, password, roles):
    found = req(
        "GET",
        f"{base}/admin/realms/{realm}/users?username={urllib.parse.quote(username)}&exact=true",
        headers=h,
    ) or []
    if found:
        uid = found[0]["id"]
        upd = {
            "enabled": True,
            "emailVerified": True,
            "email": f"{username}@asrax.in",
            "firstName": username,
            "lastName": "test",
            "requiredActions": [],
        }
        req("PUT", f"{base}/admin/realms/{realm}/users/{uid}", headers=h, data=json.dumps(upd).encode())
    else:
        body = {
            "username": username,
            "enabled": True,
            "emailVerified": True,
            "email": f"{username}@asrax.in",
            "firstName": username,
            "lastName": "test",
            "requiredActions": [],
            "credentials": [{"type": "password", "value": password, "temporary": False}],
        }
        req("POST", f"{base}/admin/realms/{realm}/users", headers=h, data=json.dumps(body).encode())
        found = req(
            "GET",
            f"{base}/admin/realms/{realm}/users?username={urllib.parse.quote(username)}&exact=true",
            headers=h,
        ) or []
        uid = found[0]["id"]

    pw = {"type": "password", "value": password, "temporary": False}
    req("PUT", f"{base}/admin/realms/{realm}/users/{uid}/reset-password", headers=h, data=json.dumps(pw).encode())

    for role in roles:
        role = role.strip()
        if not role:
            continue
        try:
            role_obj = req("GET", f"{base}/admin/realms/{realm}/roles/{role}", headers=h)
            req(
                "POST",
                f"{base}/admin/realms/{realm}/users/{uid}/role-mappings/realm",
                headers=h,
                data=json.dumps([role_obj]).encode(),
            )
        except Exception:
            pass
    print(f"user_ok={username}")


def main() -> int:
    base = os.environ["KC_BASE"].rstrip("/")
    admin = os.environ["KC_ADMIN"]
    password = os.environ["KC_PASSWORD"]
    realm = os.environ["REALM"]

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
        print("Keycloak admin token failed for test users", file=sys.stderr)
        return 1

    h = {"Authorization": f"Bearer {tok['access_token']}", "Content-Type": "application/json"}
    ensure_user(base, h, realm, os.environ["ADMIN_USER"], os.environ["ADMIN_PASS"], os.environ["ADMIN_ROLES"].split(","))
    ensure_user(base, h, realm, os.environ["USER_USER"], os.environ["USER_PASS"], os.environ["USER_ROLES"].split(","))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
