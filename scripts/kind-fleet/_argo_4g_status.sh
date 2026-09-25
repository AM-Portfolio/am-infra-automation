#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-platform.yaml
echo "=== all am-prod apps ==="
kubectl -n argocd get applications -l '' -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,DEST:.spec.destination.name' 2>/dev/null | grep -E 'prod|NAME' || kubectl -n argocd get app -o wide | head -80
echo "=== Missing/OutOfSync children ==="
kubectl -n argocd get app -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
for i in sorted(d["items"], key=lambda x: x["metadata"]["name"]):
  n=i["metadata"]["name"]
  if not n.endswith("-prod") and "prod-" not in n: continue
  sync=(i.get("status") or {}).get("sync",{}).get("status","?")
  health=(i.get("status") or {}).get("health",{}).get("status","?")
  dest=((i.get("spec") or {}).get("destination") or {}).get("name","")
  if sync!="Synced" or health not in ("Healthy","Progressing","Suspended"):
    print(f"{n:45} sync={sync:12} health={health:12} dest={dest}")
'
