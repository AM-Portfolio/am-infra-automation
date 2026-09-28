#!/usr/bin/env bash
set -euo pipefail
set -a
# shellcheck disable=SC1091
source /data/am-state/credentials/dr-infra-stores.env
set +a
ROOT="$(python3 - <<'PY'
import json
print(json.load(open("/data/am-state/vault-dr-infra.json"))["root_token"])
PY
)"
OUT=/opt/am-infra-automation/terraform/kind-fleet/dr/platform/platform.auto.tfvars
umask 077
cat >"$OUT" <<EOF
keycloak_db_password       = "${PG_USER_KEYCLOAK}"
temporal_db_password       = "${PG_USER_TEMPORAL}"
lago_db_password           = "${PG_USER_LAGO}"
n8n_db_password            = "${PG_USER_N8N}"
openproject_db_password    = "${PG_USER_OPENPROJECT}"
litellm_db_password        = "${PG_USER_LITELLM}"
langfuse_db_password       = "${PG_USER_LANGFUSE}"
growthbook_mongo_password  = "${MONGO_USER_GROWTHBOOK}"
langfuse_minio_password    = "${MINIO_USER_LANGFUSE}"
mongo_admin_password       = "${MONGO_PASSWORD}"
redis_password             = "${REDIS_PASSWORD}"
vault_token                = "${ROOT}"
vault_addr                 = "https://vault-dr.asrax.in"
EOF
chmod 600 "$OUT"
echo "wrote $OUT"
grep -E '^[a-z_]+' "$OUT" | sed 's/=.*/=***/'
