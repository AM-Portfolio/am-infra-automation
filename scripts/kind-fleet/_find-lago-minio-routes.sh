#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-infra.yaml
echo "=== IngressRoutes mentioning lago/minio/vault ==="
kubectl get ingressroute -A -o wide 2>/dev/null | grep -iE 'lago|minio|vault' || true
kubectl get ingressroute -A -o yaml 2>/dev/null | grep -nE 'lago\.|minio|Host\(' | head -40 || true
echo "=== services nodeports ==="
kubectl get svc -A | grep -iE 'lago|minio|oauth2' | head -30
echo "=== cloudflared / tunnel config snippets ==="
kubectl get configmap -A 2>/dev/null | grep -iE 'cloud|tunnel' | head -10
kubectl -n infra get cm -o name 2>/dev/null | head -20
# find ingressroute details
for ns in infra billing vault edge; do
  for ir in $(kubectl -n $ns get ingressroute -o name 2>/dev/null); do
    hosts=$(kubectl -n $ns get $ir -o jsonpath='{range .spec.routes[*]}{.match}{"\n"}{end}' 2>/dev/null || true)
    if echo "$hosts" | grep -qiE 'lago|minio|vault'; then
      echo "--- $ns/$ir ---"
      echo "$hosts"
      kubectl -n $ns get $ir -o jsonpath='{range .spec.routes[*]}{.services[0].name}:{.services[0].port}{"\n"}{end}'
    fi
  done
done
