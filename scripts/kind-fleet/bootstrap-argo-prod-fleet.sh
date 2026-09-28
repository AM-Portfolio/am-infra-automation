#!/usr/bin/env bash
# Bootstrap prod Argo fleet ApplicationSets + cluster + GitHub repo creds.
set -euo pipefail
GITOPS="${1:-/tmp/am-gitops-bootstrap}"
KCFG=/data/am-state/kubeconfig.am-prod-infra.yaml
APPS_CFG=/data/am-state/kubeconfig.am-prod-apps.yaml
TOKEN_FILE="${GITHUB_TOKEN_FILE:-/tmp/github-pat-argo}"
export KUBECONFIG="$KCFG"

test -f "$GITOPS/projects/am-prod.yaml"
test -f "$GITOPS/application-sets/apps-prod-fleet.yaml"
test -f "$APPS_CFG"

echo "=== AppProject ==="
kubectl apply -f "$GITOPS/projects/am-prod.yaml"

echo "=== GitHub repo credential for AM-Portfolio ==="
if [[ -f "$TOKEN_FILE" ]]; then
  TOKEN="$(tr -d ' \r\n' < "$TOKEN_FILE")"
  kubectl -n argocd create secret generic repo-am-portfolio \
    --from-literal=type=git \
    --from-literal=url=https://github.com/AM-Portfolio \
    --from-literal=password="$TOKEN" \
    --from-literal=username=git \
    --dry-run=client -o yaml | kubectl apply -f -
  # Org-wide credential template (not per-repo "repository" / typo "repo").
  kubectl -n argocd label secret repo-am-portfolio \
    argocd.argoproj.io/secret-type=repo-creds --overwrite
  echo "repo-am-portfolio applied (repo-creds)"
else
  echo "WARN missing $TOKEN_FILE"
fi

echo "=== Cluster secret am-prod-apps ==="
APPS_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-prod-apps-control-plane | awk '{print $1}')"
test -n "$APPS_IP"
export SERVER="https://${APPS_IP}:6443"
export CA="$(kubectl --kubeconfig "$APPS_CFG" config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
export CERT="$(kubectl --kubeconfig "$APPS_CFG" config view --raw -o jsonpath='{.users[0].user.client-certificate-data}')"
export KEY="$(kubectl --kubeconfig "$APPS_CFG" config view --raw -o jsonpath='{.users[0].user.client-key-data}')"
python3 - <<'PY'
import json, os
cfg = {
  "tlsClientConfig": {
    "insecure": False,
    "caData": os.environ["CA"],
    "certData": os.environ["CERT"],
    "keyData": os.environ["KEY"],
  }
}
open("/tmp/argo-cluster-config.json","w").write(json.dumps(cfg))
print("wrote cluster config for", os.environ["SERVER"])
PY
kubectl -n argocd create secret generic cluster-am-prod-apps \
  --from-literal=name=am-prod-apps \
  --from-literal=server="$SERVER" \
  --from-file=config=/tmp/argo-cluster-config.json \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd label secret cluster-am-prod-apps \
  argocd.argoproj.io/secret-type=cluster --overwrite
echo "cluster-am-prod-apps -> $SERVER"

echo "=== Namespaces on apps cluster ==="
kubectl --kubeconfig "$APPS_CFG" create namespace am-apps-prod --dry-run=client -o yaml | kubectl --kubeconfig "$APPS_CFG" apply -f -
kubectl --kubeconfig "$APPS_CFG" create namespace am-agents-prod --dry-run=client -o yaml | kubectl --kubeconfig "$APPS_CFG" apply -f -

echo "=== ApplicationSets ==="
kubectl apply -f "$GITOPS/application-sets/apps-prod-fleet.yaml"
kubectl apply -f "$GITOPS/application-sets/agents-prod-fleet.yaml"

echo "=== Result (wait 8s) ==="
sleep 8
kubectl -n argocd get applicationset
echo "app_count=$(kubectl -n argocd get applications --no-headers 2>/dev/null | wc -l)"
kubectl -n argocd get applications -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status --no-headers 2>/dev/null | head -30
# show ApplicationSet conditions if zero apps
if [[ "$(kubectl -n argocd get applications --no-headers 2>/dev/null | wc -l)" -eq 0 ]]; then
  kubectl -n argocd describe applicationset am-apps-prod-fleet | tail -40
fi
echo "DONE"
