#!/usr/bin/env bash
set -euo pipefail
KCFG=/data/am-state/kubeconfig.am-prod-infra.yaml
kubectl --kubeconfig "$KCFG" -n argocd get cm argocd-cm -o jsonpath='{.data.oidc\.config}' ; echo
echo '---'
kubectl --kubeconfig "$KCFG" -n argocd get cm argocd-cm -o jsonpath='{.data.url}' ; echo
echo '--- rbac ---'
kubectl --kubeconfig "$KCFG" -n argocd get cm argocd-rbac-cm -o jsonpath='{.data.policy\.csv}' ; echo
# check if oidc secret present
kubectl --kubeconfig "$KCFG" -n argocd get secret argocd-secret -o json | python3 -c 'import json,sys,base64; d=json.load(sys.stdin)["data"]; print("has_oidc_secret", "oidc.argocd.clientSecret" in d); print("keys", sorted(d.keys()))'
