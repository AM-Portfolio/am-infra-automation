#!/usr/bin/env bash
set -euo pipefail
sleep 3
echo "=== docker ports ==="
docker port hermes || true
echo "=== ss host ==="
ss -lntp | grep 8642 || true
ss -lntp | grep 9119 || true
echo "=== inside listen ==="
docker exec hermes sh -c 'ss -lntp || netstat -lntp' 2>/dev/null | head -50 || true
echo "=== curl ==="
curl -sS -o /dev/null -w "bridge8642:%{http_code}\n" --connect-timeout 3 http://172.18.0.1:8642/ || echo bridge8642:fail
curl -sS -o /dev/null -w "bridge9119:%{http_code}\n" --connect-timeout 3 http://172.18.0.1:9119/ || echo bridge9119:fail
docker exec hermes sh -c 'curl -sS -o /dev/null -w "in8642:%{http_code}\n" --connect-timeout 3 http://127.0.0.1:8642/ || echo in8642:fail'
docker exec hermes sh -c 'curl -sS -o /dev/null -w "in9119:%{http_code}\n" --connect-timeout 3 http://127.0.0.1:9119/ || echo in9119:fail'
echo "=== logs ==="
docker logs hermes 2>&1 | tail -60
