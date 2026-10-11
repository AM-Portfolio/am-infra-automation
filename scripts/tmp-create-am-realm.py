#!/usr/bin/env python3
"""Create Keycloak realm 'am' if missing (admin secret in identity/). Never prints secrets."""
import base64
import json
import subprocess
import sys

CTX = "prod-infra"


def main() -> int:
    admin = json.loads(
        subprocess.check_output(
            ["kubectl", "--context", CTX, "-n", "identity", "get", "secret", "keycloak-admin", "-o", "json"],
            text=True,
        )
    )["data"]
    user = "admin"
    pw = base64.b64decode(admin["password"]).decode()
    print(f"admin_user={user} pw_len={len(pw)}")

    remote = r"""
set -euo pipefail
RESP=$(curl -sS -X POST 'http://127.0.0.1:8080/realms/master/protocol/openid-connect/token' \
  -d client_id=admin-cli -d "username=$KC_USER" -d "password=$KC_PASS" -d grant_type=password)
TOKEN=$(printf '%s' "$RESP" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
if [[ -z "$TOKEN" ]]; then echo "TOKEN_FAIL"; printf '%s\n' "$RESP" | head -c 120; exit 1; fi
CODE=$(curl -sS -o /tmp/realm-create.json -w '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"realm":"am","enabled":true,"displayName":"AM"}' \
  http://127.0.0.1:8080/admin/realms)
echo REALM_CREATE_HTTP=$CODE
curl -sS -o /dev/null -w 'DISC_%{http_code}\n' \
  http://127.0.0.1:8080/realms/am/.well-known/openid-configuration
"""
    r = subprocess.run(
        [
            "kubectl",
            "--context",
            CTX,
            "-n",
            "identity",
            "exec",
            "keycloak-0",
            "--",
            "env",
            f"KC_USER={user}",
            f"KC_PASS={pw}",
            "bash",
            "-lc",
            remote,
        ],
        capture_output=True,
        text=True,
    )
    sys.stdout.write(r.stdout)
    sys.stderr.write(r.stderr)
    return r.returncode


if __name__ == "__main__":
    raise SystemExit(main())
