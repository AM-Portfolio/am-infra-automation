#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
for POD in am-notification-prod-5cbdb8b967-xrbpr am-subscription-prod-846b9667bb-rt5cn am-user-platform-prod-85cb8db9bd-rgk4h; do
  echo "======== $POD ========"
  kubectl -n am-apps-prod get pod "$POD" -o wide 2>&1 || { echo missing; continue; }
  echo "--- events ---"
  kubectl -n am-apps-prod describe pod "$POD" 2>&1 | tail -35
  echo "--- volumes ---"
  kubectl -n am-apps-prod get pod "$POD" -o jsonpath='{range .status.containerStatuses[*]}{.name} ready={.ready} state={.state}{"\n"}{end}{range .status.initContainerStatuses[*]}init {.name} state={.state}{"\n"}{end}' 2>&1
  echo
done
echo "=== wave ==="
pgrep -af wave_4g || echo no_wave
tail -20 /tmp/wave_4g.log 2>/dev/null || true
