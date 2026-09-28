#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-infra.yaml
BODY='{"role":"am-admin","redirect_uri":"https://vault.asrax.in/ui/vault/auth/oidc/oidc/callback"}'

echo "=== vault helm values snippet ==="
kubectl -n vault get secret vault-config -o yaml 2>/dev/null | head -5 || true
kubectl -n vault get cm -o name | head
# vault config from pod
kubectl -n vault exec vault-0 -- cat /vault/config/extraconfig-from-values.hcl 2>/dev/null || \
kubectl -n vault exec vault-0 -- ls /vault/config/ 2>/dev/null || true
kubectl -n vault exec vault-0 -- sh -c 'ls /vault/config; for f in /vault/config/*; do echo ==== $f; cat $f; done' 2>/dev/null | head -80

echo "=== via traefik pod Host header ==="
# find traefik pod
TPOD=$(kubectl -n infra get pod -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}')
echo "traefik=$TPOD"
# curl from a debug pod to traefik service with Host
kubectl -n infra run vcurl --rm -i --restart=Never --image=curlimages/curl:8.5.0 --restart=Never -- \
  curl -s -w "\ncode=%{http_code}\n" -X PUT \
  -H "Content-Type: application/json" \
  -H "Host: vault.asrax.in" \
  -d "$BODY" \
  "http://traefik.infra.svc/v1/auth/oidc/oidc/auth_url" 2>&1 | tail -20 || true

echo "=== mounts via traefik ==="
kubectl -n infra run vcurl2 --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- \
  curl -s -H "Host: vault.asrax.in" "http://traefik.infra.svc/v1/sys/internal/ui/mounts" 2>&1 | tail -30 || true

echo "=== public mounts vs nodeport request_ids / cluster ==="
curl -s https://vault.asrax.in/v1/sys/health | python3 -m json.tool
source /data/am-state/credentials/prod/vault-root.env
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-prod-infra-control-plane)
VNP=$(kubectl -n vault get svc vault -o jsonpath='{.spec.ports[?(@.port==8200)].nodePort}')
curl -s "http://${IP}:${VNP}/v1/sys/health" | python3 -m json.tool
