#!/usr/bin/env bash
set -euo pipefail
echo "=== contabo vault cluster (nodeport) ==="
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-infra.yaml
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-prod-infra-control-plane)
VNP=$(kubectl -n vault get svc vault -o jsonpath='{.spec.ports[?(@.port==8200)].nodePort}')
curl -s "http://${IP}:${VNP}/v1/sys/health" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["cluster_name"], d["cluster_id"], d["version"])'

echo "=== public vault.asrax.in cluster ==="
curl -s https://vault.asrax.in/v1/sys/health | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["cluster_name"], d["cluster_id"], d["version"])'

echo "=== cloudflared container tunnel id (from token payload, no secret) ==="
TOK=$(docker inspect am-cloudflared --format '{{range .Args}}{{.}} {{end}}' | tr ' ' '\n' | grep -E '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' | head -1 || true)
# token is after --token in Cmd
TOK=$(docker inspect am-cloudflared --format '{{json .Config.Cmd}}' | python3 -c 'import json,sys; c=json.load(sys.stdin); print(c[c.index("--token")+1] if "--token" in c else "")')
python3 - <<PY
import json, base64, os
tok = """$TOK"""
parts = tok.split(".")
# JWT payload
pad = parts[1] + "=" * (-len(parts[1]) % 4)
payload = json.loads(base64.urlsafe_b64decode(pad.encode()))
print("tunnel_id", payload.get("t"))
print("account_tag", payload.get("a"))
print("keys", sorted(payload.keys()))
PY

echo "=== traefik origin health via tunnel path ==="
# From inside: what does Host vault hit?
kubectl -n infra run vcurl3 --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- \
  curl -s -H "Host: vault.asrax.in" http://traefik.infra.svc/v1/sys/health 2>&1 | tail -5
