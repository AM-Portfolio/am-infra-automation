#!/usr/bin/env bash
# Prod Vault init + KV + policy + watcher secret. Run on VPS1 as root.
set -euo pipefail

KUBE="${KUBECONFIG:-/data/am-state/kubeconfig.am-prod-infra.yaml}"
KEYS="/data/am-state/vault-prod-infra.json"
export KUBECONFIG="$KUBE"

deadline=$((SECONDS + 480))
pod=""
while (( SECONDS < deadline )); do
  pod=$(kubectl -n vault get pod -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  phase=$(kubectl -n vault get pod "${pod:-}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [[ "$phase" == "Running" ]]; then
    break
  fi
  sleep 5
done
[[ -n "${pod:-}" ]] || { echo "vault pod not found"; exit 1; }

init=false
if ! status=$(kubectl -n vault exec "$pod" -- vault status -format=json 2>/dev/null); then
  init=true
else
  if echo "$status" | grep -Eq '"initialized"[[:space:]]*:[[:space:]]*false'; then
    init=true
  fi
fi

if [[ "$init" == "true" && ! -f "$KEYS" ]]; then
  kubectl -n vault exec "$pod" -- vault operator init -key-shares=1 -key-threshold=1 -format=json > "$KEYS"
  chmod 600 "$KEYS"
  chown am-ops:am-ops "$KEYS" || true
fi

if [[ ! -f "$KEYS" ]]; then
  echo "missing $KEYS"
  exit 1
fi

UNSEAL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["unseal_keys_b64"][0])' "$KEYS")
ROOT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["root_token"])' "$KEYS")

kubectl -n vault exec "$pod" -- vault operator unseal "$UNSEAL" >/dev/null || true
kubectl -n vault exec "$pod" -- /bin/sh -c "VAULT_TOKEN=$ROOT vault secrets enable -path=apps kv-v2" \
  || echo "apps mount may already exist"

cat >/tmp/am-apps-read.hcl <<'HCL'
path "apps/data/prod/*" { capabilities = ["create","read","update","list"] }
path "apps/metadata/prod/*" { capabilities = ["list"] }
path "secret/data/prod/*" { capabilities = ["read","list"] }
path "secret/metadata/prod/*" { capabilities = ["list"] }
HCL

kubectl -n vault cp /tmp/am-apps-read.hcl "$pod:/tmp/am-apps-read.hcl"
kubectl -n vault exec "$pod" -- /bin/sh -c "VAULT_TOKEN=$ROOT vault policy write am-apps-read /tmp/am-apps-read.hcl"

kubectl -n vault create secret generic vault-unseal-keys \
  --from-file=keys.json="$KEYS" \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart watcher so it reloads real keys
kubectl -n vault delete pod -l app=vault-unsealer-watcher --wait=false || true

echo "vault init/kv/policy/unseal-secret OK"
