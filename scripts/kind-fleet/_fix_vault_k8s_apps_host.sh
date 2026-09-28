#!/usr/bin/env bash
# Fix auth/kubernetes-apps TokenReview host to Contabo am-prod-apps CP (G25).
# Run on Contabo VPS as am-ops. No secrets committed.
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/data/am-state/kubeconfig.am-prod-apps.yaml}"
VAULT_ADDR="${VAULT_ADDR:-https://vault.asrax.in}"

if [[ -z "${VAULT_TOKEN:-}" ]]; then
  if [[ -f /data/am-state/vault-prod-infra.json ]]; then
    VAULT_TOKEN="$(python3 -c 'import json; print(json.load(open("/data/am-state/vault-prod-infra.json"))["root_token"])')"
    export VAULT_TOKEN
  elif [[ -f /data/am-state/credentials/prod/fleet/vault-root.env ]]; then
    # shellcheck disable=SC1091
    source /data/am-state/credentials/prod/fleet/vault-root.env
  elif [[ -f /data/am-state/credentials/prod/vault-root.env ]]; then
    # shellcheck disable=SC1091
    source /data/am-state/credentials/prod/vault-root.env
  else
    echo "VAULT_TOKEN not found" >&2
    exit 1
  fi
fi

APPS_IP="$(docker inspect -f '{{(index .NetworkSettings.Networks "kind").IPAddress}}' am-prod-apps-control-plane 2>/dev/null || true)"
if [[ -z "$APPS_IP" ]]; then
  # Fallback: first network IP (single-network Kind)
  APPS_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-prod-apps-control-plane)"
fi
HOST="https://${APPS_IP}:6443"
echo "apps_cp_ip=$APPS_IP host=$HOST"

# Prefer docker DNS when resolvable from vault (more stable across IP churn)
export KUBECONFIG_INFRA="${KUBECONFIG_INFRA:-/data/am-state/kubeconfig.am-prod-infra.yaml}"
if KUBECONFIG="$KUBECONFIG_INFRA" kubectl -n vault exec vault-0 -- \
  wget -qO- --timeout=3 --no-check-certificate https://am-prod-apps-control-plane:6443/healthz >/dev/null 2>&1; then
  HOST="https://am-prod-apps-control-plane:6443"
  echo "using_dns_host=$HOST"
fi

JWT="$(kubectl -n kube-system create token vault-auth-reviewer --duration=8760h)"
CA="$(kubectl get cm -n kube-system kube-root-ca.crt -o jsonpath='{.data.ca\.crt}')"

export HOST JWT CA VAULT_ADDR VAULT_TOKEN
python3 <<'PY'
import json, os, ssl, urllib.request, urllib.error

addr = os.environ["VAULT_ADDR"].rstrip("/")
token = os.environ["VAULT_TOKEN"]
body = {
    "kubernetes_host": os.environ["HOST"],
    "kubernetes_ca_cert": os.environ["CA"],
    "token_reviewer_jwt": os.environ["JWT"],
    "disable_iss_validation": True,
}
ctx = ssl.create_default_context()
req = urllib.request.Request(
    f"{addr}/v1/auth/kubernetes-apps/config",
    data=json.dumps(body).encode(),
    headers={"X-Vault-Token": token, "Content-Type": "application/json"},
    method="POST",
)
try:
    with urllib.request.urlopen(req, context=ctx, timeout=45) as r:
        print("WRITE", r.status)
except urllib.error.HTTPError as e:
    print("WRITE_FAIL", e.code, e.read().decode())
    raise

req2 = urllib.request.Request(
    f"{addr}/v1/auth/kubernetes-apps/config",
    headers={"X-Vault-Token": token},
)
with urllib.request.urlopen(req2, context=ctx, timeout=30) as r:
    d = json.load(r)["data"]
    print("host=", d.get("kubernetes_host"))
    print("disable_iss=", d.get("disable_iss_validation"))
PY

SA_JWT="$(kubectl -n am-apps-prod create token am-backend-sa --duration=10m)"
export SA_JWT
python3 <<'PY'
import json, os, ssl, urllib.request, urllib.error

addr = os.environ["VAULT_ADDR"].rstrip("/")
body = {"role": "am-backend-role", "jwt": os.environ["SA_JWT"]}
ctx = ssl.create_default_context()
req = urllib.request.Request(
    f"{addr}/v1/auth/kubernetes-apps/login",
    data=json.dumps(body).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)
try:
    with urllib.request.urlopen(req, context=ctx, timeout=45) as r:
        d = json.load(r)
        print("LOGIN_OK policies=", d.get("auth", {}).get("policies"))
except urllib.error.HTTPError as e:
    print("LOGIN_FAIL", e.code, e.read().decode())
    raise
PY
