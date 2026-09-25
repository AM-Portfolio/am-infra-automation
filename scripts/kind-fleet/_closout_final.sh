#!/bin/bash
set -euo pipefail
tail -3 /tmp/closout_sync.log
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
echo "=== not ready ==="
kubectl get pods -n am-apps-prod --no-headers | while read n r s rest; do
  a=${r%%/*}; b=${r##*/}; [ "$a" = "$b" ] && [ "$s" = "Running" ] || echo "$n $r $s"
done
kubectl get pods -n am-agents-prod --no-headers | while read n r s rest; do
  a=${r%%/*}; b=${r##*/}; [ "$a" = "$b" ] && [ "$s" = "Running" ] || echo "$n $r $s"
done
echo "=== latest ==="
for ns in am-apps-prod am-agents-prod; do
  kubectl -n "$ns" get deploy -o json | python3 -c 'import json,sys
d=json.load(sys.stdin)
for i in d.get("items") or []:
  for c in i["spec"]["template"]["spec"].get("containers") or []:
    img=c.get("image","")
    if img.endswith(":latest"):
      print(i["metadata"]["namespace"], i["metadata"]["name"], img)'
done
echo "(end latest)"
curl -sk https://am.asrax.in/qa/health | python3 -c 'import sys,json; d=json.load(sys.stdin); print("qa", d.get("status"), d.get("store"))'
