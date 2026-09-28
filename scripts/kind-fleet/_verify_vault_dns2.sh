#!/usr/bin/env bash
set -euo pipefail
echo "=== DNS resolution ==="
dig +short vault.asrax.in CNAME || true
dig +short vault.asrax.in A || true
getent hosts vault.asrax.in || true

echo "=== CF trace / which tunnel? ==="
# Compare cluster via curl with cache bypass
curl -s -H "Cache-Control: no-cache" "https://vault.asrax.in/v1/sys/health?$(date +%s)" | python3 -m json.tool

echo "=== auth_url again ==="
curl -s -o /tmp/au.json -w "%{http_code}\n" -X PUT -H "Content-Type: application/json" \
  -H "Cache-Control: no-cache" \
  -d '{"role":"am-admin","redirect_uri":"https://vault.asrax.in/ui/vault/auth/oidc/oidc/callback"}' \
  "https://vault.asrax.in/v1/auth/oidc/oidc/auth_url"
python3 -m json.tool </tmp/au.json

# Check if prod tunnel even has connection and vault route from Contabo
docker ps --format '{{.Names}} {{.Image}}' | grep -i cloudflare || true
