#!/bin/bash
set -euo pipefail
TOKEN=$(tr -d '\r\n' < /data/am-state/obs/secrets/cloudflared.token)
printf 'TUNNEL_TOKEN=%s\n' "$TOKEN" > /data/am-state/obs/secrets/cloudflared.env
chown am-ops:am-ops /data/am-state/obs/secrets/cloudflared.token /data/am-state/obs/secrets/cloudflared.env
chmod 600 /data/am-state/obs/secrets/cloudflared.token /data/am-state/obs/secrets/cloudflared.env
echo "token_len=${#TOKEN}"
docker rm -f am-obs-cf-test am-obs-cloudflared-1 2>/dev/null || true
docker pull cloudflare/cloudflared:latest
docker run -d --name am-obs-cf-test --network am-obs \
  -e TUNNEL_TOKEN="$TOKEN" \
  cloudflare/cloudflared:latest tunnel --no-autoupdate run
sleep 8
docker logs am-obs-cf-test --tail 40 2>&1 || true
docker ps -a --filter name=am-obs-cf
