#!/bin/bash
# Emit {"ip":"<docker IP of am-prod-apps-control-plane>"}
set -euo pipefail
NAME="am-prod-apps-control-plane"
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NAME" 2>/dev/null | head -1)
if [ -z "$IP" ]; then
  echo "docker inspect failed for $NAME" >&2
  exit 1
fi
printf '{"ip":"%s"}\n' "$IP"
