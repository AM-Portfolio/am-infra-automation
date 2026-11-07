#!/usr/bin/env bash
# Contabo nonprod: Hermes gateway + dashboard, MCP → public GitNexus.
# Secrets stay on host under /opt/am/hermes (never commit).
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/opt/am/hermes}"
IMAGE="${HERMES_IMAGE:-nousresearch/hermes-agent:latest}"
API_PORT=8642
DASH_PORT=9119

mkdir -p "$HERMES_HOME"
chmod 700 "$HERMES_HOME"

if [[ ! -f "$HERMES_HOME/.api_server_key" ]]; then
  openssl rand -hex 32 > "$HERMES_HOME/.api_server_key"
  chmod 600 "$HERMES_HOME/.api_server_key"
fi
API_SERVER_KEY=$(cat "$HERMES_HOME/.api_server_key")

# MCP → team GitNexus (HTTP)
cat > "$HERMES_HOME/config.yaml" <<'YAML'
mcp_servers:
  gitnexus:
    url: "https://gitnexus.asrax.in/api/mcp"
    timeout: 180
    connect_timeout: 60
    tools:
      resources: false
      prompts: false

tool_loop_guardrails:
  hard_stop_enabled: true
  hard_stop_after:
    exact_failure: 5
    idempotent_no_progress: 5
YAML

# .env: remote model only. Prefer LiteLLM OpenAI-compat when key present.
# Operator: set OPENAI_API_KEY (LiteLLM virtual/master) in this file; do not commit.
if [[ ! -f "$HERMES_HOME/.env" ]]; then
  cat > "$HERMES_HOME/.env" <<EOF
# Remote LLM via LiteLLM (OpenAI-compatible). Fill OPENAI_API_KEY before chat works.
OPENAI_BASE_URL=https://litellm.munish.org/v1
OPENAI_API_KEY=
API_SERVER_ENABLED=true
API_SERVER_HOST=0.0.0.0
API_SERVER_KEY=${API_SERVER_KEY}
API_SERVER_CORS_ORIGINS=*
HERMES_DASHBOARD=1
EOF
  chmod 600 "$HERMES_HOME/.env"
fi

echo "[hermes] pull $IMAGE"
docker pull "$IMAGE"

if docker ps -a --format '{{.Names}}' | grep -qx hermes; then
  echo "[hermes] recreate container"
  docker rm -f hermes || true
fi

docker run -d \
  --name hermes \
  --restart unless-stopped \
  --memory=4g \
  --cpus=2 \
  -v "$HERMES_HOME:/opt/data" \
  -p 172.18.0.1:${API_PORT}:8642 \
  -p 172.18.0.1:${DASH_PORT}:9119 \
  -e HERMES_DASHBOARD=1 \
  -e API_SERVER_ENABLED=true \
  -e API_SERVER_HOST=0.0.0.0 \
  -e "API_SERVER_KEY=${API_SERVER_KEY}" \
  -e 'API_SERVER_CORS_ORIGINS=*' \
  "$IMAGE" gateway run

sleep 5
docker ps --filter name=hermes --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
curl -sS -o /dev/null -w "api_local:%{http_code}\n" "http://127.0.0.1:${API_PORT}/" || true
curl -sS -o /dev/null -w "dash_local:%{http_code}\n" "http://127.0.0.1:${DASH_PORT}/" || true
# MCP connectivity from container (best-effort)
docker exec hermes hermes mcp test gitnexus 2>&1 | tail -40 || true
echo HERMES_DEPLOY_DONE
echo "API key file: $HERMES_HOME/.api_server_key"
echo "Add OPENAI_API_KEY to $HERMES_HOME/.env then: docker restart hermes"
