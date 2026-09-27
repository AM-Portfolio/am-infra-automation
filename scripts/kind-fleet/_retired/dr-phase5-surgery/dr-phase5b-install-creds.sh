#!/usr/bin/env bash
# Install Argo GitHub repo-creds + GHCR pull secrets for DR apps (from credentials.env).
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin

CREDS=/data/am-state/credentials/credentials.env
test -f "$CREDS"

# shellcheck disable=SC1090
set -a
# parse KEY=VAL without sourcing (avoid exec)
GH_TOKEN=$(python3 - <<'PY'
from pathlib import Path
keys=("GHCR_TOKEN","GITHUB_TOKEN","GH_TOKEN","GITHUB_PERSONAL_ACCESS_TOKEN")
vals={}
for line in Path("/data/am-state/credentials/credentials.env").read_text(encoding="utf-8-sig").splitlines():
  line=line.strip()
  if not line or line.startswith("#") or "=" not in line: continue
  k,_,v=line.partition("=")
  vals[k.strip()]=v.strip().strip("\"'")
tok=""
for k in keys:
  if vals.get(k): tok=vals[k]; break
print(tok)
PY
)
GH_USER=$(python3 - <<'PY'
from pathlib import Path
vals={}
for line in Path("/data/am-state/credentials/credentials.env").read_text(encoding="utf-8-sig").splitlines():
  line=line.strip()
  if not line or line.startswith("#") or "=" not in line: continue
  k,_,v=line.partition("=")
  vals[k.strip()]=v.strip().strip("\"'")
print(vals.get("GHCR_USERNAME") or vals.get("GITHUB_USER") or vals.get("GITHUB_USERNAME") or "token")
PY
)
test -n "$GH_TOKEN"
echo "token_len=${#GH_TOKEN} user=$GH_USER"

# --- Argo repo-creds (org-wide) ---
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml
kubectl -n argocd delete secret repo-github-am-portfolio --ignore-not-found
kubectl -n argocd create secret generic repo-github-am-portfolio \
  --from-literal=type=git \
  --from-literal=url=https://github.com/AM-Portfolio \
  --from-literal=username="$GH_USER" \
  --from-literal=password="$GH_TOKEN"
kubectl -n argocd label secret repo-github-am-portfolio \
  argocd.argoproj.io/secret-type=repo-creds --overwrite
echo "argo repo-creds created"

# bounce repo-server
kubectl -n argocd delete pod -l app.kubernetes.io/name=argocd-repo-server --force --grace-period=0 2>/dev/null || true
kubectl -n argocd wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-repo-server --timeout=120s

# --- GHCR pull secrets on apps cluster ---
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
AUTH=$(printf '%s:%s' "$GH_USER" "$GH_TOKEN" | base64 -w0 2>/dev/null || printf '%s:%s' "$GH_USER" "$GH_TOKEN" | base64)
DOCKERCFG=$(python3 - <<PY
import json, os
print(json.dumps({"auths":{"ghcr.io":{"username":os.environ["GH_USER"],"password":os.environ["GH_TOKEN"],"auth":os.environ["AUTH"]}}}))
PY
)
export GH_USER GH_TOKEN AUTH
DOCKERCFG=$(GH_USER="$GH_USER" GH_TOKEN="$GH_TOKEN" AUTH="$AUTH" python3 -c 'import json,os; print(json.dumps({"auths":{"ghcr.io":{"username":os.environ["GH_USER"],"password":os.environ["GH_TOKEN"],"auth":os.environ["AUTH"]}}}))')

for NS in am-apps-dr am-agents-dr edge; do
  for NAME in ghcr-creds github-registry-secret regcred; do
    kubectl -n "$NS" delete secret "$NAME" --ignore-not-found
    kubectl -n "$NS" create secret docker-registry "$NAME" \
      --docker-server=ghcr.io \
      --docker-username="$GH_USER" \
      --docker-password="$GH_TOKEN"
  done
done
echo "ghcr pull secrets created in apps+agents+edge"

# refresh a sample app
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml
sleep 10
kubectl -n argocd annotate application am-gateway-dr argocd.argoproj.io/refresh=hard --overwrite 2>/dev/null || true
sleep 15
kubectl -n argocd get application am-gateway-dr -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}{.status.conditions[*].message}{"\n"}' | head -5

echo PHASE5B_CREDS_OK
