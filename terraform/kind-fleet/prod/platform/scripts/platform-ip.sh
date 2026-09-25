#!/bin/bash
# Emit Docker IPv4 of am-prod-platform-control-plane for cross-cluster-http.
set -euo pipefail
NODE=am-prod-platform-control-plane
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NODE" 2>/dev/null | head -1)
if [ -z "$IP" ]; then
  echo '{"error":"platform control-plane not found"}' >&2
  exit 1
fi
# Prefer IPv4 only (first space-separated)
IP=$(echo "$IP" | awk '{print $1}')
printf '{"ip":"%s"}\n' "$IP"
