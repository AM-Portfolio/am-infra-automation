#!/usr/bin/env bash
set -euo pipefail
HERMES_HOME=/opt/am/hermes
PASS_FILE="$HERMES_HOME/.dashboard_password"
if [[ ! -f "$PASS_FILE" ]]; then
  openssl rand -base64 18 | tr -d '/+=' | head -c 20 > "$PASS_FILE"
  chmod 600 "$PASS_FILE"
fi
PASS=$(cat "$PASS_FILE")
HASH=$(docker exec hermes python -c "from plugins.dashboard_auth.basic import hash_password; print(hash_password('''$PASS'''))")

# Merge dashboard auth + mcp into config.yaml
python3 - <<PY
from pathlib import Path
import yaml
p = Path("/opt/am/hermes/config.yaml")
cfg = yaml.safe_load(p.read_text()) if p.exists() else {}
if not isinstance(cfg, dict):
    cfg = {}
cfg.setdefault("mcp_servers", {})
cfg["mcp_servers"]["gitnexus"] = {
    "url": "https://gitnexus.asrax.in/api/mcp",
    "timeout": 180,
    "connect_timeout": 60,
    "tools": {"resources": False, "prompts": False},
}
cfg["dashboard"] = {
    "basic_auth": {
        "username": "am-ops",
        "password_hash": """$HASH""",
    },
    "public_url": "https://hermes.asrax.in",
}
cfg["tool_loop_guardrails"] = {
    "hard_stop_enabled": True,
    "hard_stop_after": {"exact_failure": 5, "idempotent_no_progress": 5},
}
p.write_text(yaml.safe_dump(cfg, sort_keys=False))
print("config_updated")
PY

docker restart hermes
sleep 8
curl -sS -o /dev/null -w "bridge9119:%{http_code}\n" --connect-timeout 5 http://172.18.0.1:9119/ || echo bridge9119:fail
curl -sS -o /dev/null -w "bridge8642:%{http_code}\n" --connect-timeout 5 http://172.18.0.1:8642/health || \
  curl -sS -o /dev/null -w "bridge8642root:%{http_code}\n" --connect-timeout 5 http://172.18.0.1:8642/ || true
docker exec hermes hermes mcp test gitnexus 2>&1 | tail -15 || true
echo "dashboard_user=am-ops"
echo "dashboard_password_file=$PASS_FILE"
