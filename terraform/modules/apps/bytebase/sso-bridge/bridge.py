#!/usr/bin/env python3
"""Bytebase SSO bridge: after oauth2-proxy/Keycloak, mint Bytebase web cookies (Community)."""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

UPSTREAM = os.environ.get("BYTEBASE_UPSTREAM", "http://bytebase.infra.svc:80").rstrip("/")
ADMIN_EMAIL = os.environ["BYTEBASE_ADMIN_EMAIL"]
ADMIN_PASSWORD = os.environ["BYTEBASE_ADMIN_PASSWORD"]
SSO_SEED = os.environ.get("BYTEBASE_SSO_SEED", "")
PORT = int(os.environ.get("PORT", "8080"))

EMAIL_HEADERS = (
    "X-Forwarded-Email",
    "X-Auth-Request-Email",
    "X-Forwarded-User",
)


def derived_password(email: str) -> str:
    raw = hmac.new(
        SSO_SEED.encode() if SSO_SEED else b"am-bytebase-sso",
        email.lower().encode(),
        hashlib.sha256,
    ).hexdigest()
    return raw[:32]


def http_json(method: str, path: str, body: dict | None = None, token: str | None = None):
    data = None if body is None else json.dumps(body).encode()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = Request(UPSTREAM + path, data=data, method=method, headers=headers)
    try:
        with urlopen(req, timeout=30) as resp:
            raw = resp.read()
            cookies = resp.headers.get_all("Set-Cookie") or []
            payload = json.loads(raw.decode()) if raw else {}
            return resp.status, payload, cookies
    except HTTPError as e:
        raw = e.read().decode() if e.fp else ""
        try:
            payload = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            payload = {"message": raw}
        return e.code, payload, []


def admin_token() -> str:
    code, payload, _ = http_json(
        "POST",
        "/v1/auth/login",
        {"email": ADMIN_EMAIL, "password": ADMIN_PASSWORD},
    )
    if code >= 400 or "token" not in payload:
        raise RuntimeError(f"admin login failed: {code} {payload}")
    return payload["token"]


def _adminish(groups: str) -> bool:
    return any(
        g.strip() in {"am-admin", "access-bytebase-dba", "am-ops"}
        for g in (groups or "").replace(";", ",").split(",")
    )


def ensure_iam(email: str, groups: str, token: str) -> None:
    """Bind Keycloak user into workspace IAM (Community has no native OIDC roles)."""
    code, payload, _ = http_json("GET", "/v1/workspaces", token=token)
    workspaces = (payload or {}).get("workspaces") or []
    if not workspaces:
        return
    ws = workspaces[0]["name"]  # workspaces/<id>
    code, policy, _ = http_json("GET", f"/v1/{ws}:getIamPolicy", token=token)
    if code >= 400 or not isinstance(policy, dict):
        return
    member = f"user:{email}"
    want_role = (
        "roles/workspaceAdmin" if _adminish(groups) else "roles/workspaceMember"
    )
    bindings = policy.setdefault("bindings", [])
    # Already bound at wanted (or higher) role?
    for b in bindings:
        members = b.get("members") or []
        if member in members:
            if b.get("role") == want_role or (
                want_role == "roles/workspaceMember"
                and b.get("role") == "roles/workspaceAdmin"
            ):
                return
            # Downgrade path unused — leave admin as-is
            if b.get("role") == "roles/workspaceAdmin":
                return
    # Ensure binding exists
    target = None
    for b in bindings:
        if b.get("role") == want_role:
            target = b
            break
    if target is None:
        target = {"role": want_role, "members": [], "condition": {}}
        bindings.append(target)
    members = target.setdefault("members", [])
    if member not in members:
        members.append(member)
    http_json(
        "POST",
        f"/v1/{ws}:setIamPolicy",
        {"policy": policy},
        token=token,
    )


def ensure_user(email: str, title: str, groups: str) -> None:
    token = admin_token()
    pw = derived_password(email)
    # Try create
    code, payload, _ = http_json(
        "POST",
        "/v1/users",
        {"email": email, "title": title or email.split("@")[0], "password": pw},
        token=token,
    )
    if code in (200, 201):
        pass
    else:
        # User may exist — reset password so SSO can mint cookies
        http_json(
            "PATCH",
            f"/v1/users/{email}?update_mask=password",
            {"password": pw},
            token=token,
        )
    try:
        ensure_iam(email, groups, token)
    except Exception as e:
        print(f"ensure_iam warning for {email}: {e}", flush=True)


def mint_web_cookies(email: str) -> list[str]:
    pw = derived_password(email)
    code, payload, cookies = http_json(
        "POST",
        "/v1/auth/login",
        {"email": email, "password": pw, "web": True},
    )
    if code >= 400 or not cookies:
        raise RuntimeError(f"web login failed for {email}: {code} {payload}")
    # Lax survives Keycloak → oauth2 top-level redirects; Secure only when edge is HTTPS
    # (oauth2-proxy sets X-Forwarded-Proto).
    out = []
    for c in cookies:
        c = re.sub(r"(?i)SameSite=Strict", "SameSite=Lax", c)
        if "SameSite=" not in c:
            c = c + "; SameSite=Lax"
        out.append(c)
    return out


def extract_email(headers: dict[str, str]) -> str:
    for h in EMAIL_HEADERS:
        v = headers.get(h) or headers.get(h.lower())
        if v and "@" in v:
            return v.strip().lower()
        if v and h.endswith("User") and "@" not in v:
            # username only — skip
            continue
    return ""


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        print("[%s] %s" % (self.log_date_time_string(), fmt % args), flush=True)

    def _headers_dict(self) -> dict[str, str]:
        return {k: v for k, v in self.headers.items()}

    def _has_bb_session(self) -> bool:
        cookie = self.headers.get("Cookie", "")
        return "access-token=" in cookie or "refresh-token=" in cookie

    def _proxy(self, extra_req_headers: dict[str, str] | None = None) -> None:
        length = int(self.headers.get("Content-Length", "0") or 0)
        body = self.rfile.read(length) if length > 0 else None
        headers = {}
        for k, v in self.headers.items():
            lk = k.lower()
            if lk in ("host", "content-length", "connection", "transfer-encoding"):
                continue
            headers[k] = v
        if extra_req_headers:
            headers.update(extra_req_headers)
        url = UPSTREAM + self.path
        req = Request(url, data=body, method=self.command, headers=headers)
        try:
            with urlopen(req, timeout=120) as resp:
                data = resp.read()
                self.send_response(resp.status)
                for hk, hv in resp.headers.items():
                    if hk.lower() in ("transfer-encoding", "connection", "content-length"):
                        continue
                    self.send_header(hk, hv)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(data)
        except HTTPError as e:
            data = e.read()
            self.send_response(e.code)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except URLError as e:
            msg = f"upstream error: {e}".encode()
            self.send_response(502)
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)

    def _sso_redirect(self) -> bool:
        if self._has_bb_session():
            return False
        # Only auto-login browser navigations
        accept = self.headers.get("Accept", "")
        if self.command not in ("GET", "HEAD"):
            return False
        if "text/html" not in accept and "*/*" not in accept and accept != "":
            # API calls without session — still try if email present? skip
            if "application/json" in accept:
                return False
        email = extract_email(self._headers_dict())
        if not email:
            return False
        groups = (
            self.headers.get("X-Forwarded-Groups")
            or self.headers.get("X-Auth-Request-Groups")
            or ""
        )
        title = self.headers.get("X-Forwarded-Preferred-Username") or email.split("@")[0]
        try:
            ensure_user(email, title, groups)
            cookies = mint_web_cookies(email)
        except Exception as e:
            msg = f"SSO bridge failed: {e}".encode()
            self.send_response(500)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)
            return True
        # Redirect so browser stores cookies then loads app
        dest = self.path if self.path.startswith("/") else "/"
        xf_proto = (self.headers.get("X-Forwarded-Proto") or "").lower()
        secure_edge = xf_proto == "https"
        self.send_response(302)
        for c in cookies:
            if secure_edge and "Secure" not in c:
                c = c + "; Secure"
            self.send_header("Set-Cookie", c)
        self.send_header("Location", dest)
        self.send_header("Content-Length", "0")
        self.end_headers()
        return True

    def do_GET(self):  # noqa: N802
        if self.path in ("/healthz", "/readyz"):
            body = b"ok"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path.startswith("/oauth2/"):
            self._proxy()
            return
        if self._sso_redirect():
            return
        self._proxy()

    def do_HEAD(self):  # noqa: N802
        self.do_GET()

    def do_POST(self):  # noqa: N802
        self._proxy()

    def do_PUT(self):  # noqa: N802
        self._proxy()

    def do_PATCH(self):  # noqa: N802
        self._proxy()

    def do_DELETE(self):  # noqa: N802
        self._proxy()


def main() -> None:
    if not re.match(r"^[^@]+@[^@]+\.[^@]+$", ADMIN_EMAIL):
        raise SystemExit("BYTEBASE_ADMIN_EMAIL invalid")
    print(f"bytebase-sso-bridge listening on :{PORT} upstream={UPSTREAM}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
