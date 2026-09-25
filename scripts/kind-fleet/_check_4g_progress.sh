#!/bin/bash
set -euo pipefail
echo "=== wave ==="
pgrep -af wave_4g || echo no_wave
tail -40 /tmp/wave_4g.log 2>/dev/null || true
echo "=== markers ==="
grep -E 'READY|WAVE_4G|deploy not|sync failed|timeout' /tmp/wave_4g.log 2>/dev/null | tail -40 || true
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
echo "=== apps Missing/NotReady ==="
kubectl -n am-apps-prod get deploy -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas,AVAIL:.status.availableReplicas' 2>/dev/null | grep -E 'NAME|0 |<none>' || true
kubectl -n am-apps-prod get pods --field-selector=status.phase!=Running --no-headers 2>/dev/null | head -20 || true
echo "=== agents ==="
kubectl -n am-agents-prod get deploy -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas' 2>/dev/null
kubectl -n am-agents-prod get pods --no-headers 2>/dev/null
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-platform.yaml
echo "=== argo remaining ==="
for a in am-asrax-corp-prod am-asrax-ui-prod am-api-gateway-prod am-support-agent-prod am-qa-agents-prod am-fin-agent-prod am-db-agent-prod am-mkt-agents-prod am-mkt-portal-ui-prod am-logging-prod; do
  sync=$(kubectl -n argocd get app $a -o jsonpath='{.status.sync.status}' 2>/dev/null || echo missing)
  health=$(kubectl -n argocd get app $a -o jsonpath='{.status.health.status}' 2>/dev/null || echo missing)
  echo "$a sync=$sync health=$health"
done
