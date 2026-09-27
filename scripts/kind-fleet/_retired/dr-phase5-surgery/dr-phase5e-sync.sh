#!/usr/bin/env bash
# Phase 5e: sync am-market-data and wait for Ready.
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml
PASS=$(cd /opt/am-infra-automation/terraform/kind-fleet/dr/platform && terraform output -raw argocd_admin_password)

echo "=== refresh + sync am-market-data-dr ==="
kubectl -n argocd exec deploy/argocd-server -- sh -c \
  "argocd login localhost:8080 --username admin --password '$PASS' --plaintext --grpc-web >/dev/null && \
   argocd app get am-market-data-dr --refresh --server localhost:8080 --plaintext --grpc-web >/dev/null && \
   argocd app sync am-market-data-dr --server localhost:8080 --plaintext --grpc-web --prune --timeout 420" \
  2>&1 | tee /tmp/dr-5e-sync.log | tail -50

echo "=== argo status ==="
kubectl -n argocd get applications am-market-data-dr \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status --no-headers

export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
kubectl rollout status deploy/am-market-data-dr -n am-apps-dr --timeout=300s || true
kubectl get pods -n am-apps-dr | grep -iE 'NAME|market'
kubectl get ingress -n am-apps-dr am-market-data-dr -o wide 2>&1 || true

echo "=== domain smoke ==="
curl -sS -o /tmp/mkt-health.body -w "health %{http_code}\n" --connect-timeout 15 -m 45 \
  "https://am-dr.asrax.in/market/actuator/health" || true
head -c 200 /tmp/mkt-health.body; echo
curl -sS -o /tmp/mkt-quotes.body -w "quotes %{http_code}\n" --connect-timeout 15 -m 45 \
  "https://am-dr.asrax.in/market/v1/market-data/quotes?symbols=RELIANCE" || true
head -c 300 /tmp/mkt-quotes.body; echo

echo "=== gate 4e ==="
cd /opt/am-infra-automation
PYTHONPATH=scripts/kind-fleet python3 -m phase_gates --env dr --wave 4e 2>&1 | tee /tmp/dr-gate4e.log | tail -40
