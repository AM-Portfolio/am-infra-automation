#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
echo "=== SPC google objects ==="
kubectl -n am-apps-prod get secretproviderclass am-email-extractor-prod-vault-secrets -o jsonpath='{.spec.parameters.objects}' | python3 -c '
import sys,yaml
objs=yaml.safe_load(sys.stdin.read())
for o in objs:
  if "google" in o.get("objectName","").lower() or "oauth" in o.get("objectName","").lower():
    print(o)
'
echo "=== CSI provider logs (last) ==="
kubectl -n kube-system logs -l app.kubernetes.io/name=vault-csi-provider --tail=30 2>/dev/null || kubectl -n vault logs -l app=vault-csi-provider --tail=30 2>/dev/null || true
kubectl get pods -A | grep -i csi | head -20
