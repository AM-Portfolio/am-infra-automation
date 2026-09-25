#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
POD=$(kubectl -n am-agents-prod get pods -l app.kubernetes.io/instance=am-fin-agent-prod -o jsonpath='{.items[0].metadata.name}')
echo "POD=$POD"
kubectl -n am-agents-prod describe pod "$POD" | tail -20
echo "=== SPC ==="
kubectl -n am-agents-prod get secretproviderclass am-fin-agent-prod-vault-secrets -o jsonpath='{.spec.parameters.objects}'
echo
