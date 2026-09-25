#!/bin/bash
set -euo pipefail
for p in /qa/health /spt-poc/health /qa/api/platform/health /spt-poc/api/platform/health /qa/ready /spt-poc/ready; do
  code=$(curl -sk -o /tmp/qh.json -w '%{http_code}' "https://am.asrax.in${p}")
  body=$(python3 -c 'print(open("/tmp/qh.json","rb").read()[:120].decode("utf-8","replace").replace("\n"," "))')
  echo "$p $code $body"
done
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
kubectl -n am-agents-prod get pods -l app.kubernetes.io/instance=am-qa-agents-prod
