#!/usr/bin/env python3
"""Configure am-realm, roles, G24 OIDC clients, 24h sessions, and JWT role mappers."""
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


def ensure_mapper(h, base, realm, client_uuid, mapper):
    """Idempotent protocol mapper on a client (match by name)."""
    existing = (
        req(
            "GET",
            f"{base}/admin/realms/{realm}/clients/{client_uuid}/protocol-mappers/models",
            headers=h,
        )
        or []
    )
    for m in existing:
        if m.get("name") == mapper["name"]:
            mid = m["id"]
            mapper["id"] = mid
            req(
                "PUT",
                f"{base}/admin/realms/{realm}/clients/{client_uuid}/protocol-mappers/models/{mid}",
                headers=h,
                data=json.dumps(mapper).encode(),
            )
            return
    req(
        "POST",
        f"{base}/admin/realms/{realm}/clients/{client_uuid}/protocol-mappers/models",
        headers=h,
        data=json.dumps(mapper).encode(),
    )


def ensure_client_scope(h, base, realm, name, claim_name):
    """Create OIDC client scope + realm-role mapper (Argo/Vault/oauth2-proxy request these)."""
    scopes = req("GET", f"{base}/admin/realms/{realm}/client-scopes", headers=h) or []
    scope = next((s for s in scopes if s.get("name") == name), None)
    payload = {
        "name": name,
        "protocol": "openid-connect",
        "attributes": {
            "include.in.token.scope": "true",
            "display.on.consent.screen": "false",
        },
        "description": f"AM realm roles as {claim_name} claim",
    }
    if scope:
        sid = scope["id"]
        payload["id"] = sid
        req(
            "PUT",
            f"{base}/admin/realms/{realm}/client-scopes/{sid}",
            headers=h,
            data=json.dumps({**scope, **payload}).encode(),
        )
    else:
        req(
            "POST",
            f"{base}/admin/realms/{realm}/client-scopes",
            headers=h,
            data=json.dumps(payload).encode(),
        )
        scopes = req("GET", f"{base}/admin/realms/{realm}/client-scopes", headers=h) or []
        scope = next((s for s in scopes if s.get("name") == name), None)
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
            "claim.name": claim_name,
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
    for m in existing:
        if m.get("name") == mapper["name"]:
            mid = m["id"]
            mapper["id"] = mid
            req(
                "PUT",
                f"{base}/admin/realms/{realm}/client-scopes/{sid}/protocol-mappers/models/{mid}",
                headers=h,
                data=json.dumps(mapper).encode(),
            )
            break
    else:
        req(
            "POST",
            f"{base}/admin/realms/{realm}/client-scopes/{sid}/protocol-mappers/models",
            headers=h,
            data=json.dumps(mapper).encode(),
        )
    return sid


def attach_default_scope(h, base, realm, client_uuid, scope_id, scope_name):
    """Attach client scope as default (idempotent)."""
    defaults = (
        req(
            "GET",
            f"{base}/admin/realms/{realm}/clients/{client_uuid}/default-client-scopes",
            headers=h,
        )
        or []
    )
    if any(s.get("id") == scope_id or s.get("name") == scope_name for s in defaults):
        return
    optionals = (
        req(
            "GET",
            f"{base}/admin/realms/{realm}/clients/{client_uuid}/optional-client-scopes",
            headers=h,
        )
        or []
    )
    if any(s.get("id") == scope_id or s.get("name") == scope_name for s in optionals):
        # promote optional → default
        req(
            "DELETE",
            f"{base}/admin/realms/{realm}/clients/{client_uuid}/optional-client-scopes/{scope_id}",
            headers=h,
        )
    req(
        "PUT",
        f"{base}/admin/realms/{realm}/clients/{client_uuid}/default-client-scopes/{scope_id}",
        headers=h,
    )


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

    # SSO ~24h (iam-sso Phase 1)
    try:
        r = req("GET", f"{base}/admin/realms/{realm}", headers=h)
        r["ssoSessionIdleTimeout"] = 86400
        r["ssoSessionMaxLifespan"] = 86400
        r["accessTokenLifespan"] = 3600
        r["accessTokenLifespanForImplicitFlow"] = 3600
        r["clientSessionIdleTimeout"] = 86400
        r["clientSessionMaxLifespan"] = 86400
        r["offlineSessionIdleTimeout"] = 2592000
        req("PUT", f"{base}/admin/realms/{realm}", headers=h, data=json.dumps(r).encode())
    except Exception as e:
        print(f"session_ttl_skipped: {e}")

    for role in roles:
        try:
            req("GET", f"{base}/admin/realms/{realm}/roles/{role}", headers=h)
        except Exception:
            req(
                "POST",
                f"{base}/admin/realms/{realm}/roles",
                headers=h,
                data=json.dumps({"name": role}).encode(),
            )

    try:
        ra = req(
            "GET",
            f"{base}/admin/realms/{realm}/authentication/required-actions/CONFIGURE_TOTP",
            headers=h,
        )
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
    # OAuth scopes Argo / Vault / oauth2-proxy / Headlamp / MinIO request.
    # Without these client-scopes Keycloak returns invalid_scope.
    groups_scope_id = ensure_client_scope(h, base, realm, "groups", "groups")
    roles_scope_id = ensure_client_scope(h, base, realm, "roles", "roles")
    print(f"client_scopes groups={groups_scope_id} roles={roles_scope_id}")

    role_mappers = [
        {
            "name": "am-realm-roles",
            "protocol": "openid-connect",
            "protocolMapper": "oidc-usermodel-realm-role-mapper",
            "consentRequired": False,
            "config": {
                "multivalued": "true",
                "userinfo.token.claim": "true",
                "id.token.claim": "true",
                "access.token.claim": "true",
                "claim.name": "roles",
                "jsonType.label": "String",
            },
        },
        {
            "name": "am-groups-from-roles",
            "protocol": "openid-connect",
            "protocolMapper": "oidc-usermodel-realm-role-mapper",
            "consentRequired": False,
            "config": {
                "multivalued": "true",
                "userinfo.token.claim": "true",
                "id.token.claim": "true",
                "access.token.claim": "true",
                "claim.name": "groups",
                "jsonType.label": "String",
            },
        },
    ]

    for c in clients:
        existing = (
            req(
                "GET",
                f"{base}/admin/realms/{realm}/clients?clientId={urllib.parse.quote(c['clientId'])}",
                headers=h,
            )
            or []
        )
        payload = {
            "clientId": c["clientId"],
            "enabled": True,
            "protocol": "openid-connect",
            "publicClient": bool(c.get("publicClient", False)),
            "secret": c.get("secret") or "",
            "redirectUris": c["redirectUris"],
            "webOrigins": c.get("webOrigins") or [],
            "standardFlowEnabled": True,
            "directAccessGrantsEnabled": direct_grants,
            "attributes": {"post.logout.redirect.uris": "##".join(c["redirectUris"])},
        }
        if c.get("publicClient"):
            payload["secret"] = None
            payload.pop("secret", None)
            payload["publicClient"] = True
        body = json.dumps({k: v for k, v in payload.items() if v is not None}).encode()
        if existing:
            cid = existing[0]["id"]
            req("PUT", f"{base}/admin/realms/{realm}/clients/{cid}", headers=h, data=body)
        else:
            req("POST", f"{base}/admin/realms/{realm}/clients", headers=h, data=body)
            existing = (
                req(
                    "GET",
                    f"{base}/admin/realms/{realm}/clients?clientId={urllib.parse.quote(c['clientId'])}",
                    headers=h,
                )
                or []
            )
            cid = existing[0]["id"] if existing else None
        if not existing:
            continue
        cid = existing[0]["id"]
        for mapper in role_mappers:
            try:
                ensure_mapper(h, base, realm, cid, dict(mapper))
            except Exception as e:
                print(f"mapper_skipped client={c['clientId']} name={mapper['name']}: {e}")
        try:
            attach_default_scope(h, base, realm, cid, groups_scope_id, "groups")
            attach_default_scope(h, base, realm, cid, roles_scope_id, "roles")
        except Exception as e:
            print(f"scope_attach_skipped client={c['clientId']}: {e}")

    print(
        f"realm_ok={realm} clients={len(clients)} mfa_enforce={str(mfa).lower()} "
        f"direct_grants={direct_grants} sso_max=86400 scopes=groups,roles"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
