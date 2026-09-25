#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
POD=$(kubectl -n am-agents-prod get pods -l app.kubernetes.io/instance=am-qa-agents-prod -o jsonpath='{.items[0].metadata.name}')
echo "POD=$POD"
kubectl -n am-agents-prod logs "$POD" --tail=80 2>&1 | grep -iE 'init_db|create_all|Application startup|ERROR|UndefinedTable|permission|Traceback' | grep -vE 'password|secret|token' | tail -30
echo "=== init_db ==="
kubectl -n am-agents-prod exec "$POD" -- bash -lc 'cd /app/qa-agent && PYTHONPATH=/app/qa-agent python3 -c "
import os
print(\"SPT_STORE\", os.getenv(\"SPT_STORE\"))
print(\"URL_set\", bool(os.getenv(\"SPT_DATABASE_URL\")))
from specs.persistence.db.engine import init_db, get_engine, database_url
from sqlalchemy import text, inspect
u=database_url()
print(\"scheme\", u.split(\":\",1)[0])
try:
  init_db(); print(\"init_db OK\")
except Exception as e:
  print(\"init_db FAIL\", type(e).__name__, e)
eng=get_engine()
with eng.connect() as c:
  print(\"db\", c.execute(text(\"SELECT current_database(), current_schema(), current_user\")).fetchone())
  print(\"tables\", inspect(eng).get_table_names())
"'
