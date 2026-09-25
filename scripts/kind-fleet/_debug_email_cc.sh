#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
POD=$(kubectl -n am-apps-prod get pods -l app.kubernetes.io/instance=am-email-extractor-prod --field-selector=status.phase!=Succeeded -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
echo "POD=$POD"
kubectl -n am-apps-prod describe pod "$POD" 2>&1 | tail -40
echo "=== SPC paths ==="
kubectl -n am-apps-prod get secretproviderclass am-email-extractor-prod-vault-secrets -o jsonpath='{.spec.parameters.objects}' 2>/dev/null | tr '\n' ' ' | fold -s -w 120
echo
echo "=== wave ==="
pgrep -af wave_4g || echo no_wave
tail -15 /tmp/wave_4g.log 2>/dev/null || true
