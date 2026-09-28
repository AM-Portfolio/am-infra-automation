#!/usr/bin/env bash
# Patch argocd-secret with OIDC client secret from /data/am-state/credentials/<env>/oidc.env
set -euo pipefail
ENV="${1:-prod}"
KCFG="${KUBECONFIG:-/data/am-state/kubeconfig.am-${ENV}-infra.yaml}"
OIDC="/data/am-state/credentials/${ENV}/oidc.env"
test -f "$OIDC"
# shellcheck disable=SC1090
set -a
# parse without sourcing whole file blindly
SECRET="$(grep '^OIDC_ARGOCD_CLIENT_SECRET=' "$OIDC" | head -1 | cut -d= -f2-)"
test -n "$SECRET"
B64="$(printf '%s' "$SECRET" | base64 -w0 2>/dev/null || printf '%s' "$SECRET" | base64)"
kubectl --kubeconfig "$KCFG" -n argocd patch secret argocd-secret --type merge \
  -p "{\"data\":{\"oidc.argocd.clientSecret\":\"${B64}\"}}"
echo "patched oidc.argocd.clientSecret"
kubectl --kubeconfig "$KCFG" -n argocd rollout restart deploy/argocd-server 2>/dev/null \
  || kubectl --kubeconfig "$KCFG" -n argocd rollout restart statefulset/argocd-server 2>/dev/null \
  || true
# verify
kubectl --kubeconfig "$KCFG" -n argocd get secret argocd-secret -o json \
  | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]; print("has_oidc_secret", "oidc.argocd.clientSecret" in d)'
