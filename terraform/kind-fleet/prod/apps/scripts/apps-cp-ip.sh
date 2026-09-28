#!/bin/bash
# Emit {"ip":"<docker IP of am-prod-apps-control-plane>"}
# Prefer Kind bridge network — bare {{range}} concatenates multi-net IPs and can
# drift to infra worker addresses after docker network reshuffles.
set -euo pipefail
NAME="am-prod-apps-control-plane"
IP=$(docker inspect -f '{{(index .NetworkSettings.Networks "kind").IPAddress}}' "$NAME" 2>/dev/null || true)
if [ -z "$IP" ]; then
  IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NAME" 2>/dev/null | head -1)
fi
if [ -z "$IP" ]; then
  echo "docker inspect failed for $NAME" >&2
  exit 1
fi
printf '{"ip":"%s"}\n' "$IP"
