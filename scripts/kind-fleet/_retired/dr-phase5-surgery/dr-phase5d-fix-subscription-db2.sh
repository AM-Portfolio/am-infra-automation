#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin

export KUBECONFIG=/data/am-state/kubeconfig.am-dr-infra.yaml
PNS=infra
PPOD=postgresql-0

# Prefer postgres chart secret
ADMIN_PASS=""
for s in postgresql postgresql-0 postgres; do
  if kubectl get secret -n "$PNS" "$s" >/dev/null 2>&1; then
    for k in postgres-password postgresql-password password POSTGRES_PASSWORD; do
      v=$(kubectl get secret -n "$PNS" "$s" -o "jsonpath={.data.$k}" 2>/dev/null || true)
      if [ -n "$v" ]; then
        ADMIN_PASS=$(printf '%s' "$v" | base64 -d)
        echo "admin from secret/$s key=$k len=${#ADMIN_PASS}"
        break 2
      fi
    done
  fi
done

if [ -z "$ADMIN_PASS" ]; then
  python3 <<'PY'
import json,ssl,urllib.request
tok=json.load(open("/data/am-state/vault-dr-infra.json"))["root_token"]
ctx=ssl._create_unverified_context()
req=urllib.request.Request(
  "https://vault-dr.asrax.in/v1/apps/data/dr/infra/postgres",
  headers={"X-Vault-Token":tok,"User-Agent":"am-kind-fleet-gates/1"},
)
with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
  data=((json.loads(r.read().decode()).get("data") or {}).get("data") or {})
open("/tmp/pg-admin.pass","w").write(data.get("POSTGRES_PASSWORD") or data.get("password") or "")
print("vault keys", sorted(data.keys()))
print("vault POSTGRES_USER", data.get("POSTGRES_USER") or data.get("username"))
PY
  ADMIN_PASS=$(cat /tmp/pg-admin.pass)
  echo "admin from vault len=${#ADMIN_PASS}"
fi

APP_USER=am_subscription_user
APP_DB=am_subscription
ADMIN_USER=postgres

run_sql() {
  local sql="$1"
  kubectl exec -n "$PNS" "$PPOD" -- \
    env PGPASSWORD="$ADMIN_PASS" \
    psql -U "$ADMIN_USER" -d "$APP_DB" -v ON_ERROR_STOP=1 -c "$sql"
}

echo "=== before ==="
run_sql "SELECT tablename, tableowner FROM pg_tables WHERE schemaname='public' AND tablename LIKE 'am_subscription%' ORDER BY 1;"
run_sql "SELECT rolname FROM pg_roles WHERE rolname IN ('am_subscription_user','postgres');"

echo "=== alter ownership ==="
run_sql "ALTER TABLE IF EXISTS public.am_subscriptions OWNER TO ${APP_USER};"
# catch related tables/sequences
run_sql "DO \$\$ DECLARE r record; BEGIN FOR r IN SELECT c.relname, c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname LIKE 'am_subscription%' LOOP IF r.relkind IN ('r','p') THEN EXECUTE format('ALTER TABLE public.%I OWNER TO %I', r.relname, '${APP_USER}'); ELSIF r.relkind='S' THEN EXECUTE format('ALTER SEQUENCE public.%I OWNER TO %I', r.relname, '${APP_USER}'); END IF; END LOOP; END \$\$;"
run_sql "GRANT ALL ON SCHEMA public TO ${APP_USER};"
run_sql "GRANT ALL ON ALL TABLES IN SCHEMA public TO ${APP_USER};"
run_sql "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO ${APP_USER};"
run_sql "ALTER DATABASE ${APP_DB} OWNER TO ${APP_USER};" || echo "ALTER DATABASE skipped/failed (ok if in use)"

echo "=== after ==="
run_sql "SELECT tablename, tableowner FROM pg_tables WHERE schemaname='public' AND tablename LIKE 'am_subscription%' ORDER BY 1;"

echo "=== restart subscription ==="
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
kubectl get pods -n am-apps-dr -o name | grep subscription | xargs -r kubectl delete -n am-apps-dr --force --grace-period=0
kubectl rollout restart deploy/am-subscription-dr -n am-apps-dr
sleep 25
kubectl get pods -n am-apps-dr | grep -iE 'NAME|subscription'
kubectl logs -n am-apps-dr deploy/am-subscription-dr --tail=30 2>&1 | tail -30
kubectl rollout status deploy/am-subscription-dr -n am-apps-dr --timeout=120s || true
kubectl get pods -n am-apps-dr | grep -iE 'NAME|subscription|identity|notification|modern'
