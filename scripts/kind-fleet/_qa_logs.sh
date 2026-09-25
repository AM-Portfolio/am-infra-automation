#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
POD=$(kubectl -n am-agents-prod get pods -l app.kubernetes.io/instance=am-qa-agents-prod -o jsonpath='{.items[0].metadata.name}')
echo "POD=$POD"
kubectl -n am-agents-prod get pod "$POD"
kubectl -n am-agents-prod logs "$POD" --tail=60 2>&1 | grep -vE 'password|secret|token|ODk9|postgres:' || kubectl -n am-agents-prod logs "$POD" --tail=40 2>&1 | sed 's/[Pp]assword[^ ]*/*** /g'
echo "=== wave tail ==="
tail -15 /tmp/wave_4g.log
pgrep -af wave_4g || echo no_wave
