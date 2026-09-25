#!/bin/bash
set -euo pipefail
# Read vault keys for am-agents via a pod that can auth, or vault CLI
export VAULT_ADDR=https://vault.asrax.in
# Try vault token from kind/platform if present
if [ -f /root/.vault-token ]; then export VAULT_TOKEN=$(cat /root/.vault-token); fi
if [ -f /data/am-state/vault-root-token ]; then export VAULT_TOKEN=$(cat /data/am-state/vault-root-token); fi
if [ -z "${VAULT_TOKEN:-}" ] && [ -f /tmp/vault-token ]; then export VAULT_TOKEN=$(cat /tmp/vault-token); fi

echo "vault binary: $(command -v vault || echo none)"
echo "token set: $([ -n "${VAULT_TOKEN:-}" ] && echo yes || echo no)"

if command -v vault >/dev/null && [ -n "${VAULT_TOKEN:-}" ]; then
  echo "=== apps/prod/services/am-agents keys ==="
  vault kv get -mount=apps -format=json prod/services/am-agents 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('\n'.join(sorted(d['data']['data'].keys())))" || vault kv get apps/prod/services/am-agents 2>&1 | head -80
  echo "=== apps/prod/services/am-user-platform keys ==="
  vault kv get -mount=apps -format=json prod/services/am-user-platform 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('\n'.join(sorted(d['data']['data'].keys())))" || true
  echo "=== search AM_FIN ==="
  vault kv get -mount=apps -format=json prod/services/am-agents 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin)['data']['data']; print([k for k in d if 'FIN' in k.upper() or 'CLIENT' in k.upper() or 'MCP' in k.upper()])"
fi
