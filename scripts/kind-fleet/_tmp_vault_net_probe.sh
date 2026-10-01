#!/usr/bin/env bash
set -euo pipefail
NODE=am-prod-infra-worker
CID=$(docker exec "$NODE" crictl ps --name vault -q | head -1)
APPS_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' am-prod-apps-control-plane | awk '{print $1}')
echo "apps_ip=$APPS_IP cid=${CID:0:12}"
echo "=== vault pod resolv ==="
docker exec "$NODE" crictl exec "$CID" cat /etc/resolv.conf || true
echo "=== getent ==="
docker exec "$NODE" crictl exec "$CID" getent hosts am-prod-apps-control-plane || echo "dns_fail"
docker exec "$NODE" crictl exec "$CID" getent hosts "$APPS_IP" || true
echo "=== curl IP from vault pod ==="
docker exec "$NODE" crictl exec "$CID" sh -c "curl -sk --connect-timeout 3 https://${APPS_IP}:6443/healthz" || echo "curl_ip_fail"
echo "=== curl DNS from vault pod ==="
docker exec "$NODE" crictl exec "$CID" sh -c "curl -sk --connect-timeout 3 https://am-prod-apps-control-plane:6443/healthz" || echo "curl_dns_fail"
echo "=== curl from kind node ns ==="
docker exec "$NODE" curl -sk --connect-timeout 3 "https://${APPS_IP}:6443/healthz" || echo "node_curl_fail"
docker exec "$NODE" getent hosts am-prod-apps-control-plane || true
# hostNetwork? check vault pod
echo "=== vault pod net ==="
docker exec "$NODE" crictl inspect "$CID" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print('sandbox', d.get('info',{}).get('runtimeSpec',{}).get('hostname')); print('ip', d.get('status',{}).get('network',{}))" 2>/dev/null || true
