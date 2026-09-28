#!/usr/bin/env bash
set -euo pipefail
BODY='{"role":"am-admin","redirect_uri":"https://vault.asrax.in/ui/vault/auth/oidc/oidc/callback"}'

echo "=== public PUT auth_url ==="
curl -s -D /tmp/pub.hdr -o /tmp/pub.json -w "code=%{http_code}\n" \
  -X PUT -H "Content-Type: application/json" -d "$BODY" \
  "https://vault.asrax.in/v1/auth/oidc/oidc/auth_url"
echo "--- headers ---"
cat /tmp/pub.hdr
echo "--- body ---"
python3 -m json.tool </tmp/pub.json || cat /tmp/pub.json

echo "=== public GET health ==="
curl -s -o /dev/null -w "health=%{http_code}\n" "https://vault.asrax.in/v1/sys/health"

echo "=== public GET ui mounts ==="
curl -s -o /tmp/uim.json -w "mounts=%{http_code}\n" "https://vault.asrax.in/v1/sys/internal/ui/mounts"
python3 -c 'import json; d=json.load(open("/tmp/uim.json")); print(list((d.get("data") or {}).get("auth",{}).keys()) if "data" in d else d)'

# Compare via in-cluster curl to vault service (Traefik Host header)
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-infra.yaml
echo "=== in-cluster to vault svc ==="
kubectl -n vault run curl-vault-oidc --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- \
  -s -o /tmp/out -w "%{http_code}" -X PUT -H "Content-Type: application/json" -d "$BODY" \
  "http://vault.vault.svc:8200/v1/auth/oidc/oidc/auth_url" || true
