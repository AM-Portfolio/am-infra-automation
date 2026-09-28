#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-infra.yaml
echo "=== all IngressRoutes ==="
kubectl get ingressroute -A 2>/dev/null
kubectl get ingressroute.traefik.containo.us -A 2>/dev/null || true
echo "=== lago/minio related ==="
kubectl get ingressroute -A -o yaml 2>/dev/null | grep -nE 'lago|minio|Host\(`' | head -50
# cloudflared
echo "=== cloudflared ==="
docker exec am-cloudflared sh -c 'ls /etc/cloudflared 2>/dev/null; cat /etc/cloudflared/config.yml 2>/dev/null | head -120' 2>/dev/null || \
docker exec am-cloudflared cat /etc/cloudflared/config.yaml 2>/dev/null | head -120 || true
