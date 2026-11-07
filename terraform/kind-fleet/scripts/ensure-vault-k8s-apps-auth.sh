#!/usr/bin/env bash
# Re-point Vault auth/kubernetes-apps (G25) at Contabo am-prod-apps API.
# Vault pods cannot resolve Docker DNS; SoT is live Kind node IP :6443, refreshed
# on kind-fleet-boot / after Docker restart.
#
# Usage (root on Contabo VPS):
#   ENV=prod bash ensure-vault-k8s-apps-auth.sh
#   bash ensure-vault-k8s-apps-auth.sh prod
#
# Requires: docker + crictl on Kind nodes, kubectl via ASRAX kubeconfigs,
# VAULT_TOKEN or /data/am-state/vault-<env>-infra.json / credentials/<env>/vault-root.env
set -euo pipefail

ENV_NAME="${1:-${ENV:-prod}}"
ASRAX_HOME="${ASRAX_HOME:-/home/am-ops/.asrax}"
APPS_CP="am-${ENV_NAME}-apps-control-plane"
INFRA_CP="am-${ENV_NAME}-infra-control-plane"
AUTH_PATH="${VAULT_K8S_APPS_PATH:-kubernetes-apps}"
ROLE_NAME="${VAULT_K8S_APPS_ROLE:-am-backend-role}"
APPS_NS="am-apps-${ENV_NAME}"
[[ "$ENV_NAME" == "prod" ]] && APPS_NS="am-apps-prod"
[[ "$ENV_NAME" == "dr" ]] && APPS_NS="am-apps-dr"

echo "== ensure-vault-k8s-apps-auth ENV=$ENV_NAME =="

load_vault_token() {
  if [[ -n "${VAULT_TOKEN:-}" ]]; then
    return 0
  fi
  if [[ -f /data/am-state/vault-${ENV_NAME}-infra.json ]]; then
    VAULT_TOKEN="$(python3 -c "import json; print(json.load(open('/data/am-state/vault-${ENV_NAME}-infra.json'))['root_token'])")"
    export VAULT_TOKEN
    return 0
  fi
  if [[ -f /data/am-state/credentials/${ENV_NAME}/vault-root.env ]]; then
    # shellcheck disable=SC1090
    set -a; source "/data/am-state/credentials/${ENV_NAME}/vault-root.env"; set +a
    return 0
  fi
  echo "ERROR: VAULT_TOKEN not found" >&2
  exit 1
}

load_vault_token
if [[ -z "${VAULT_TOKEN:-}" ]]; then
  echo "ERROR: empty VAULT_TOKEN" >&2
  exit 1
fi
echo "vault_token_len=${#VAULT_TOKEN} prefix=${VAULT_TOKEN:0:6}"

# --- locate vault container on infra Kind node ---
VAULT_NODE=""
VAULT_CID=""
for n in "${ENV_NAME}-infra-worker" "am-${ENV_NAME}-infra-worker" "am-${ENV_NAME}-infra-control-plane"; do
  # normalize
  :
done
for n in "am-${ENV_NAME}-infra-worker" "am-${ENV_NAME}-infra-control-plane"; do
  if docker inspect "$n" >/dev/null 2>&1; then
    cid=$(docker exec "$n" crictl ps --name vault -q 2>/dev/null | head -1 || true)
    if [[ -n "$cid" ]]; then
      VAULT_NODE="$n"
      VAULT_CID="$cid"
      break
    fi
  fi
done
if [[ -z "$VAULT_CID" ]]; then
  echo "ERROR: vault container not found on infra Kind nodes" >&2
  exit 1
fi
echo "vault_runtime node=$VAULT_NODE cid=${VAULT_CID:0:12}"

vexec() {
  local args_q
  args_q=$(python3 -c 'import shlex,sys; print(" ".join(shlex.quote(a) for a in sys.argv[1:]))' "$@")
  docker exec "$VAULT_NODE" crictl exec "$VAULT_CID" \
    sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=$(printf %q "$VAULT_TOKEN") vault $args_q"
}

# Vault runs as a Pod — it cannot resolve Docker DNS names like am-prod-apps-control-plane
# (pod resolv → cluster CoreDNS). Use live Kind node IP :6443, refreshed on each boot.
# (Optional) also add CoreDNS hosts on infra so the DNS name works later.
APPS_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$APPS_CP" | awk '{print $1}')
IP_HOST="https://${APPS_IP}:6443"
DNS_HOST="https://${APPS_CP}:6443"

vault_pod_healthz() {
  local url="$1"
  docker exec "$VAULT_NODE" crictl exec "$VAULT_CID" \
    sh -c "wget -qO- --timeout=3 --no-check-certificate '${url}/healthz'" >/dev/null 2>&1
}

HOST="$IP_HOST"
if vault_pod_healthz "$IP_HOST"; then
  echo "apps_api reachable from vault pod via IP $IP_HOST"
  HOST="$IP_HOST"
elif vault_pod_healthz "$DNS_HOST"; then
  echo "apps_api reachable from vault pod via DNS $DNS_HOST"
  HOST="$DNS_HOST"
else
  echo "WARN: healthz from vault pod failed; writing IP host=$IP_HOST anyway"
  HOST="$IP_HOST"
fi
echo "kubernetes_host_will_write=$HOST"

# Apps CA + reviewer JWT via local kubeconfigs
rewrite_kc() {
  local src="$1" cp="$2" dst="$3"
  local ip
  ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$cp" | awk '{print $1}')
  python3 - "$src" "$ip" "$dst" <<'PY'
import re, socket, sys
src, ip, dst = sys.argv[1], sys.argv[2], sys.argv[3]
t = open(src).read()
for port in (6443, 6444):
    try:
        s = socket.create_connection((ip, port), 2); s.close()
        open(dst, "w").write(re.sub(r"(https?://)[^\s]+", f"https://{ip}:{port}", t, count=1))
        print(f"kubeconfig -> https://{ip}:{port}", flush=True)
        break
    except OSError:
        pass
else:
    raise SystemExit(f"no API for {ip}")
PY
}

APPS_KC_SRC="${ASRAX_HOME}/kubeconfig.am-${ENV_NAME}-apps.yaml"
INFRA_KC_SRC="${ASRAX_HOME}/kubeconfig.am-${ENV_NAME}-infra.yaml"
APPS_KC=/tmp/kubeconfig.am-${ENV_NAME}-apps.vaultauth.yaml
if [[ ! -f "$APPS_KC_SRC" ]]; then
  echo "ERROR: missing $APPS_KC_SRC" >&2
  exit 1
fi
rewrite_kc "$APPS_KC_SRC" "$APPS_CP" "$APPS_KC"
export KUBECONFIG="$APPS_KC"

CA="$(kubectl get cm -n kube-public kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' 2>/dev/null \
  || kubectl get cm -n kube-system kube-root-ca.crt -o jsonpath='{.data.ca\.crt}')"
JWT="$(kubectl -n kube-system create token vault-auth-reviewer --duration=8760h)"
echo "reviewer_jwt_len=${#JWT} ca_len=${#CA}"

# Write config via vault CLI inside vault pod (avoids CF on vault.asrax.in)
printf '%s\n' "$CA" | docker exec -i "$VAULT_NODE" crictl exec -i "$VAULT_CID" sh -c 'cat > /tmp/apps-ca.crt'
# JWT via file to avoid shell escaping issues
printf '%s' "$JWT" | docker exec -i "$VAULT_NODE" crictl exec -i "$VAULT_CID" sh -c 'cat > /tmp/apps-reviewer.jwt'

vexec write "auth/${AUTH_PATH}/config" \
  "kubernetes_host=${HOST}" \
  kubernetes_ca_cert=@/tmp/apps-ca.crt \
  token_reviewer_jwt=@/tmp/apps-reviewer.jwt \
  disable_iss_validation=true

echo "=== config after ==="
# Redact PEM bodies / JWTs; only surface kubernetes_host for operators.
vexec read "auth/${AUTH_PATH}/config" 2>/dev/null \
  | awk '
      /BEGIN CERTIFICATE/ {skip=1; print "kubernetes_ca_cert=***REDACTED***"; next}
      /END CERTIFICATE/ {skip=0; next}
      skip {next}
      /(jwt|token|pem)/ {print $1"=***REDACTED***"; next}
      {print}
    ' | head -20 || true
CFG_HOST=$(vexec read -field=kubernetes_host "auth/${AUTH_PATH}/config" 2>/dev/null || true)
echo "kubernetes_host=$CFG_HOST"

# Prove login as am-backend-sa
SA_JWT="$(kubectl -n "$APPS_NS" create token am-backend-sa --duration=10m)"
printf '%s' "$SA_JWT" | docker exec -i "$VAULT_NODE" crictl exec -i "$VAULT_CID" sh -c 'cat > /tmp/sa.jwt'
if vexec write "auth/${AUTH_PATH}/login" "role=${ROLE_NAME}" jwt=@/tmp/sa.jwt >/tmp/am-vault-login.out 2>/tmp/am-vault-login.err; then
  echo "LOGIN_OK"
  grep -E '^(token_policies|policies)' /tmp/am-vault-login.out | head -5 || true
else
  echo "LOGIN_FAIL $(tr '\n' ' ' </tmp/am-vault-login.err | head -c 240)" >&2
  exit 1
fi

echo "== ensure-vault-k8s-apps-auth done =="
