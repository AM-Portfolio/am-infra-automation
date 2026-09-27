#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml

POD=$(kubectl get pods -n am-apps-dr -o name | grep market-data | head -1 | cut -d/ -f2)
echo "pod=$POD"
kubectl get pod -n am-apps-dr "$POD" -o wide
echo "=== describe events ==="
kubectl describe pod -n am-apps-dr "$POD" | tail -50
echo "=== container statuses ==="
kubectl get pod -n am-apps-dr "$POD" -o jsonpath='{range .status.containerStatuses[*]}{.name} ready={.ready} state={.state} restart={.restartCount}{"\n"}{end}{range .status.initContainerStatuses[*]}init/{.name} ready={.ready} state={.state}{"\n"}{end}'
echo
echo "=== logs ==="
kubectl logs -n am-apps-dr "$POD" --tail=80 2>&1 | tail -80
echo "=== SPC objects head ==="
kubectl get secretproviderclass -n am-apps-dr am-market-data-dr-vault-secrets -o jsonpath='{.spec.parameters.objects}' 2>/dev/null | head -c 800; echo
echo "=== synced secret keys ==="
kubectl get secret -n am-apps-dr am-market-data-dr-synced-secrets -o json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(sorted((d.get("data") or {}).keys()) if d else "missing")' || echo "no secret yet"
