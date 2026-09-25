#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
kubectl -n am-apps-prod describe pod -l app.kubernetes.io/instance=am-oms-prod 2>&1 | tail -40
echo === image ===
kubectl -n am-apps-prod get deploy am-oms-prod -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}' 2>&1
echo === pull secrets ===
kubectl -n am-apps-prod get deploy am-oms-prod -o jsonpath='{.spec.template.spec.imagePullSecrets}{"\n"}' 2>&1
