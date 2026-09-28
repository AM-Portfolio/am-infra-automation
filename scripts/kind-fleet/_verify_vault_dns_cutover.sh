#!/usr/bin/env bash
set -euo pipefail
echo "PUBLIC health:"
curl -s https://vault.asrax.in/v1/sys/health | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["cluster_name"], d["cluster_id"])'
echo "AUTH_URL:"
code=$(curl -s -o /tmp/au.json -w "%{http_code}" -X PUT -H "Content-Type: application/json" \
  -d '{"role":"am-admin","redirect_uri":"https://vault.asrax.in/ui/vault/auth/oidc/oidc/callback"}' \
  https://vault.asrax.in/v1/auth/oidc/oidc/auth_url)
echo "code=$code"
python3 -c 'import json; d=json.load(open("/tmp/au.json")); print(d.get("errors") or "ok"); print(((d.get("data") or {}).get("auth_url") or "")[:100])'
echo "MOUNTS:"
curl -s https://vault.asrax.in/v1/sys/internal/ui/mounts | python3 -c 'import json,sys; print(sorted(json.load(sys.stdin).get("data",{}).get("auth",{}).keys()))'
echo "NODEPORT:"
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-infra.yaml
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-prod-infra-control-plane)
VNP=$(kubectl -n vault get svc vault -o jsonpath='{.spec.ports[?(@.port==8200)].nodePort}')
curl -s "http://${IP}:${VNP}/v1/sys/health" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["cluster_name"], d["cluster_id"])'
