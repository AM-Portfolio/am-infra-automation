#!/bin/bash
set -euo pipefail
tail -5 /tmp/closout_sync.log
pgrep -af closout_sync_remaining || echo sync_done
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
echo "=== QA ingress ==="
kubectl -n am-agents-prod get ingress am-qa-agents-prod -o yaml | grep -E 'path:|middleware|priority|enabled' | head -20
echo "=== QA health ==="
code=$(curl -sk -o /tmp/qh.json -w '%{http_code}' https://am.asrax.in/qa/health)
echo "code=$code body=$(python3 -c 'print(open("/tmp/qh.json","rb").read()[:200].decode("utf-8","replace").replace(chr(10)," "))')"
code2=$(curl -sk -o /tmp/qh2.json -w '%{http_code}' https://am.asrax.in/qa/ready)
echo "ready=$code2 body=$(python3 -c 'print(open("/tmp/qh2.json","rb").read()[:200].decode("utf-8","replace").replace(chr(10)," "))')"
echo "=== latest images left ==="
kubectl get deploy -n am-apps-prod -n am-agents-prod -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.template.spec.containers[*]}{.image}{"\n"}{end}{end}' 2>/dev/null | grep ':latest' || kubectl get deploy -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {.spec.template.spec.containers[0].image}{"\n"}{end}' | grep -E 'am-(apps|agents)-prod' | grep latest || true
echo "=== not ready pods ==="
kubectl -n am-apps-prod get pods --no-headers | awk '$3!="Running" || $2!~/^[0-9]+\/[0-9]+$/ {print}' | head
kubectl -n am-agents-prod get pods --no-headers | awk '$3!="Running" || $2!~/^[0-9]+\/[0-9]+$/ {print}' | head
# ready ratio check
kubectl -n am-apps-prod get pods --no-headers | awk '{split($2,a,"/"); if(a[1]!=a[2]) print}'
kubectl -n am-agents-prod get pods --no-headers | awk '{split($2,a,"/"); if(a[1]!=a[2]) print}'
