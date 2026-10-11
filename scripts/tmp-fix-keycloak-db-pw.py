import base64
import json
import subprocess
import sys

CTX = "prod-infra"


def secret_data(ns: str, name: str) -> dict:
    out = subprocess.check_output(
        ["kubectl", "--context", CTX, "-n", ns, "get", "secret", name, "-o", "json"],
        text=True,
    )
    return json.loads(out).get("data") or {}


def b64d(data: dict, key: str) -> bytes:
    v = data.get(key)
    return base64.b64decode(v) if v else b""


creds = secret_data("infra", "db-creds-postgresql-keycloak")
kc = secret_data("identity", "keycloak-db")
pg = secret_data("infra", "postgresql-secret")

print("creds keys", sorted(creds), {k: len(v) for k, v in creds.items()})
print("kc keys", sorted(kc), {k: len(v) for k, v in kc.items()})
print("pg keys", sorted(pg), {k: len(v) for k, v in pg.items()})

creds_pw = b64d(creds, "DB_PASSWORD") or b64d(creds, "password")
kc_pw = b64d(kc, "password")
pg_super = (
    b64d(pg, "POSTGRES_PASSWORD")
    or b64d(pg, "postgres-password")
    or b64d(pg, "password")
)
user = (b64d(creds, "DB_USERNAME") or b64d(creds, "username") or b"?").decode()

print("username", user)
print("creds_pw_len", len(creds_pw), "kc_pw_len", len(kc_pw), "pg_super_len", len(pg_super))
print("creds_pw == kc_pw", creds_pw == kc_pw)

# Prefer SoT: db-creds-postgresql-keycloak password
sot = creds_pw or kc_pw
if not sot or not pg_super:
    print("ERROR missing sot or pg_super")
    sys.exit(1)

# Sync identity/keycloak-db if different
if kc_pw != sot:
    print("PATCH identity/keycloak-db to match db-creds")
    patch = {
        "data": {
            "password": base64.b64encode(sot).decode(),
        }
    }
    subprocess.check_call(
        [
            "kubectl",
            "--context",
            CTX,
            "-n",
            "identity",
            "patch",
            "secret",
            "keycloak-db",
            "--type",
            "merge",
            "-p",
            json.dumps(patch),
        ]
    )
else:
    print("keycloak-db already matches db-creds")

# ALTER USER in postgres
import tempfile
import os

with tempfile.TemporaryDirectory() as td:
    open(os.path.join(td, "kc.b64"), "wb").write(base64.b64encode(sot))
    open(os.path.join(td, "pg.b64"), "wb").write(base64.b64encode(pg_super))
    subprocess.check_call(
        [
            "kubectl",
            "--context",
            CTX,
            "cp",
            os.path.join(td, "kc.b64"),
            f"infra/postgresql-0:/tmp/kc.b64",
        ]
    )
    subprocess.check_call(
        [
            "kubectl",
            "--context",
            CTX,
            "cp",
            os.path.join(td, "pg.b64"),
            f"infra/postgresql-0:/tmp/pg.b64",
        ]
    )

script = r"""
set -euo pipefail
export PGPASSWORD=$(base64 -d </tmp/pg.b64)
NEWPW=$(base64 -d </tmp/kc.b64)
# dollar-quote avoids quote breakage; delimiter avoids collision with password content
psql -U postgres -v ON_ERROR_STOP=1 <<SQL
ALTER USER keycloak WITH PASSWORD \$\$amkc\$\$${NEWPW}\$\$amkc\$\$;
SQL
rm -f /tmp/kc.b64 /tmp/pg.b64
echo ALTER_OK
"""
subprocess.check_call(
    ["kubectl", "--context", CTX, "-n", "infra", "exec", "postgresql-0", "--", "bash", "-c", script]
)
subprocess.check_call(
    [
        "kubectl",
        "--context",
        CTX,
        "-n",
        "identity",
        "delete",
        "pod",
        "keycloak-0",
        "--force",
        "--grace-period=0",
    ]
)
print("DONE")
