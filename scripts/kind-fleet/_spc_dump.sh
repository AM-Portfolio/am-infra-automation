#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
for spc in am-notification-prod-vault-secrets am-subscription-prod-vault-secrets am-user-platform-prod-vault-secrets am-identity-prod-vault-secrets am-portfolio-prod-vault-secrets; do
  echo "=== $spc ==="
  kubectl -n am-apps-prod get secretproviderclass "$spc" -o json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
objs=((d.get("spec") or {}).get("parameters") or "")
# parameters is often a string YAML
print(objs[:2500] if isinstance(objs,str) else objs)
' || echo missing
  echo
done
