#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:$PATH

echo "=== IngressRoutes ==="
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-infra.yaml
kubectl get ingressroute -A 2>/dev/null | head -50

echo "=== platform pods ==="
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml
kubectl get pods -A 2>&1 | head -40
echo "=== keycloak describe/logs ==="
kubectl describe pod -n identity keycloak-0 2>&1 | tail -40
kubectl logs -n identity keycloak-0 --tail=40 2>&1 || true

echo "=== apply status ==="
pgrep -a '^terraform$' || pgrep -af 'terraform apply' || echo none
grep -E 'Error:|Apply complete' /tmp/dr-platform-apply.log | tail -20
tail -8 /tmp/dr-platform-apply.log | sed 's/\x1b\[[0-9;]*m//g'

echo "=== curl auth-dr via localhost traefik if any ==="
curl -sS -o /dev/null -w "auth-dr:%{http_code}\n" --connect-timeout 5 -k https://auth-dr.asrax.in/ 2>&1 || true
curl -sS -o /dev/null -w "argocd-dr:%{http_code}\n" --connect-timeout 5 -k https://argocd-dr.asrax.in/ 2>&1 || true
