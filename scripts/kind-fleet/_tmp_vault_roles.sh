#!/usr/bin/env bash
set -euo pipefail
bash /tmp/_tmp_vault_net_probe.sh
NODE=am-prod-infra-worker
CID=$(docker exec "$NODE" crictl ps --name vault -q | head -1)
TOK=$(python3 -c 'import json; print(json.load(open("/data/am-state/vault-prod-infra.json"))["root_token"])')
echo "=== roles ==="
docker exec "$NODE" crictl exec "$CID" sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=$(printf %q "$TOK") vault list auth/kubernetes-apps/role" || true
echo "=== role am-backend-role ==="
docker exec "$NODE" crictl exec "$CID" sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=$(printf %q "$TOK") vault read auth/kubernetes-apps/role/am-backend-role" || true
echo "=== list all role names try common ==="
for r in am-backend-role am-apps-prod am-apps-read am-backend am-apps; do
  echo "-- $r --"
  docker exec "$NODE" crictl exec "$CID" sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=$(printf %q "$TOK") vault read auth/kubernetes-apps/role/$r" 2>&1 | head -15 || true
done
