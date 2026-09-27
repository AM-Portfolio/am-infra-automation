#!/usr/bin/env bash
# Fix am-subscription-dr CrashLoop: grant table ownership for migrations.
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml

echo "=== current pods ==="
kubectl get pods -n am-apps-dr | grep -iE 'NAME|subscription' || true

echo "=== latest crash reason ==="
POD=$(kubectl get pods -n am-apps-dr --sort-by=.metadata.creationTimestamp -o name | grep subscription | tail -1 | cut -d/ -f2)
kubectl logs -n am-apps-dr "$POD" --tail=25 2>&1 | tail -25

echo "=== DB user / name from secret (lengths) ==="
python3 <<'PY'
import base64, json, subprocess
raw = subprocess.check_output(
    ["kubectl", "get", "secret", "-n", "am-apps-dr", "am-subscription-dr-synced-secrets", "-o", "json"]
)
data = json.loads(raw)["data"]
for k in ("AM_SUBSCRIPTION_DB_USER", "AM_SUBSCRIPTION_DB_NAME", "AM_SUBSCRIPTION_POSTGRES_HOST",
          "POSTGRES_USER", "POSTGRES_HOST"):
    if k in data:
        v = base64.b64decode(data[k]).decode()
        print(f"{k}={v!r}")
PY

# Resolve postgres on infra cluster (hostAliases point at infra Docker IP).
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-infra.yaml
echo "=== postgres pod ==="
kubectl get pods -A | grep -iE 'postgres|NAME' | head -20

# Prefer postgres in stores / infra namespace
NS=$(kubectl get pods -A -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
for i in d["items"]:
  name=i["metadata"]["name"]
  if "postgres" in name and "export" not in name and i["status"].get("phase")=="Running":
    print(i["metadata"]["namespace"], name)
    break
')
echo "picked: $NS"
PNS=$(echo "$NS" | awk '{print $1}')
PPOD=$(echo "$NS" | awk '{print $2}')

# Superuser creds from infra vault / secret
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
# get app role + password from synced secret
eval "$(python3 <<'PY'
import base64, json, subprocess, shlex
raw = subprocess.check_output(
    ["kubectl", "get", "secret", "-n", "am-apps-dr", "am-subscription-dr-synced-secrets", "-o", "json"]
)
data = {k: base64.b64decode(v).decode() for k,v in json.loads(raw)["data"].items()}
print(f"export APP_DB_USER={shlex.quote(data.get('AM_SUBSCRIPTION_DB_USER') or data.get('POSTGRES_USER',''))}")
print(f"export APP_DB_NAME={shlex.quote(data.get('AM_SUBSCRIPTION_DB_NAME','am_subscription'))}")
print(f"export APP_DB_PASS={shlex.quote(data.get('AM_SUBSCRIPTION_DB_PASSWORD') or data.get('POSTGRES_PASSWORD',''))}")
print(f"export PGHOST={shlex.quote(data.get('AM_SUBSCRIPTION_POSTGRES_HOST') or data.get('POSTGRES_HOST','postgres-dr.asrax.in'))}")
PY
)"

export KUBECONFIG=/data/am-state/kubeconfig.am-dr-infra.yaml
# admin password from postgres secret in cluster
ADMIN_PASS=$(kubectl get secret -n "$PNS" -o json 2>/dev/null | python3 -c '
import json,sys,base64
d=json.load(sys.stdin)
cands=[]
for item in d.get("items",[]):
  name=item["metadata"]["name"]
  data=item.get("data") or {}
  for k in ("postgres-password","POSTGRES_PASSWORD","password","postgresql-password"):
    if k in data:
      cands.append((name,k,base64.b64decode(data[k]).decode()))
print(cands[0][0]+"|"+cands[0][1]+"|"+cands[0][2] if cands else "")
' || true)

if [ -z "$ADMIN_PASS" ]; then
  # vault root read
  python3 <<'PY' > /tmp/pg-admin.env
import json,ssl,urllib.request,shlex
tok=json.load(open("/data/am-state/vault-dr-infra.json"))["root_token"]
ctx=ssl._create_unverified_context()
req=urllib.request.Request(
  "https://vault-dr.asrax.in/v1/apps/data/dr/infra/postgres",
  headers={"X-Vault-Token":tok,"User-Agent":"am-kind-fleet-gates/1"},
)
with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
  data=((json.loads(r.read().decode()).get("data") or {}).get("data") or {})
# prefer superuser fields
user=data.get("POSTGRES_SUPERUSER") or data.get("username") or data.get("POSTGRES_USER") or "postgres"
pw=data.get("POSTGRES_SUPERUSER_PASSWORD") or data.get("POSTGRES_PASSWORD") or data.get("password") or ""
print(f"ADMIN_USER={shlex.quote(user)}")
print(f"ADMIN_PASS={shlex.quote(pw)}")
print("#keys", " ".join(sorted(data.keys())))
PY
  # shellcheck disable=SC1091
  source /tmp/pg-admin.env
  echo "vault admin user=$ADMIN_USER keys_line=$(grep '^#keys' /tmp/pg-admin.env)"
else
  ADMIN_USER=postgres
  ADMIN_PASS="${ADMIN_PASS##*|}"
  echo "k8s secret admin ok"
fi

echo "=== fix ownership as $ADMIN_USER on db=$APP_DB_NAME app_user=$APP_DB_USER ==="
kubectl exec -n "$PNS" "$PPOD" -- env PGPASSWORD="$ADMIN_PASS" \
  psql -U "$ADMIN_USER" -d "$APP_DB_NAME" -v ON_ERROR_STOP=1 <<SQL
SELECT current_user, current_database();
SELECT table_schema, table_name, tableowner
FROM pg_tables
WHERE schemaname = 'public' AND table_name LIKE 'am_subscription%'
ORDER BY 1,2;

DO \$\$
DECLARE r record;
BEGIN
  -- Ensure app role owns public tables it needs to migrate
  FOR r IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r','p','v','m','S')
      AND c.relname LIKE 'am_subscription%'
  LOOP
    EXECUTE format('ALTER TABLE IF EXISTS public.%I OWNER TO %I', r.relname, '${APP_DB_USER}');
  END LOOP;

  -- Also grant on schema + future
  EXECUTE format('GRANT ALL ON SCHEMA public TO %I', '${APP_DB_USER}');
  EXECUTE format('GRANT ALL ON ALL TABLES IN SCHEMA public TO %I', '${APP_DB_USER}');
  EXECUTE format('GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO %I', '${APP_DB_USER}');
  EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO %I', '${APP_DB_USER}');
  EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO %I', '${APP_DB_USER}');
END
\$\$;

-- Prefer database ownership if safe for app user
ALTER DATABASE "${APP_DB_NAME}" OWNER TO "${APP_DB_USER}";

SELECT table_schema, table_name, tableowner
FROM pg_tables
WHERE schemaname = 'public' AND table_name LIKE 'am_subscription%'
ORDER BY 1,2;
SQL

echo "=== cleanup duplicate subscription pods / restart ==="
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
kubectl delete pods -n am-apps-dr -l app.kubernetes.io/name=am-subscription --force --grace-period=0 2>/dev/null || \
  kubectl get pods -n am-apps-dr -o name | grep subscription | xargs -r kubectl delete -n am-apps-dr --force --grace-period=0
kubectl rollout restart deploy/am-subscription-dr -n am-apps-dr
sleep 20
kubectl rollout status deploy/am-subscription-dr -n am-apps-dr --timeout=180s || true
kubectl get pods -n am-apps-dr | grep -iE 'NAME|subscription|identity|notification|modern'
kubectl logs -n am-apps-dr deploy/am-subscription-dr --tail=40 2>&1 | tail -40
