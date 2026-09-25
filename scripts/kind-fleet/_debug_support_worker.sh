#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
POD=am-support-agent-worker-5946644568-dng8c
NS=am-agents-prod
echo "=== POD ==="
kubectl -n "$NS" get pod "$POD" -o wide
echo "=== PREV LOGS ==="
kubectl -n "$NS" logs "$POD" --previous --tail=80 2>&1 | grep -vE 'password|secret|token|API_KEY|Bearer ' || true
echo "=== CURRENT LOGS ==="
kubectl -n "$NS" logs "$POD" --tail=40 2>&1 | grep -vE 'password|secret|token|API_KEY|Bearer ' || true
echo "=== DESCRIBE EVENTS ==="
kubectl -n "$NS" describe pod "$POD" | tail -35
echo "=== DEPLOY ==="
kubectl -n "$NS" get deploy am-support-agent-worker -o wide
echo "=== ENV (non-secret) ==="
kubectl -n "$NS" get deploy am-support-agent-worker -o jsonpath='{.spec.template.spec.containers[0].env[*].name}' | tr ' ' '\n' | head -40
echo
