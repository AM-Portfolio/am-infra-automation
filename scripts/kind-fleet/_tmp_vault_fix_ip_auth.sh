#!/usr/bin/env bash
# Re-write kubernetes-apps config using apps CP IP (Vault pods cannot resolve Docker DNS).
# Optionally inject CoreDNS hosts on infra for durable name.
set -euo pipefail
NODE=am-prod-infra-worker
CID=$(docker exec "$NODE" crictl ps --name vault -q | head -1)
TOK=$(python3 -c 'import json; print(json.load(open("/data/am-state/vault-prod-infra.json"))["root_token"])')
APPS_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' am-prod-apps-control-plane | awk '{print $1}')
HOST="https://${APPS_IP}:6443"
echo "HOST=$HOST"

# probe with wget (vault image has wget often)
echo "=== wget from vault pod to IP ==="
docker exec "$NODE" crictl exec "$CID" sh -c "wget -qO- --timeout=5 --no-check-certificate ${HOST}/healthz" && echo OK || echo FAIL

ASRAX_HOME=/home/am-ops/.asrax
SRC=$ASRAX_HOME/kubeconfig.am-prod-apps.yaml
OUT=/tmp/kc-apps-auth2.yaml
python3 - "$SRC" "$APPS_IP" "$OUT" <<'PY'
import re, socket, sys
src, ip, dst = sys.argv[1], sys.argv[2], sys.argv[3]
t=open(src).read()
for port in (6443,6444):
  try:
    s=socket.create_connection((ip,port),2); s.close()
    open(dst,'w').write(re.sub(r'(https?://)[^\s]+', f'https://{ip}:{port}', t, count=1))
    print('kc', ip, port); break
  except OSError:
    pass
else:
  raise SystemExit('no api')
PY
export KUBECONFIG="$OUT"
CA=$(kubectl get cm -n kube-public kube-root-ca.crt -o jsonpath='{.data.ca\.crt}')
JWT=$(kubectl -n kube-system create token vault-auth-reviewer --duration=8760h)
echo "jwt_len=${#JWT} ca_len=${#CA}"

printf '%s\n' "$CA" | docker exec -i "$NODE" crictl exec -i "$CID" sh -c 'cat > /tmp/apps-ca.crt'
printf '%s' "$JWT" | docker exec -i "$NODE" crictl exec -i "$CID" sh -c 'cat > /tmp/apps-reviewer.jwt'

docker exec "$NODE" crictl exec "$CID" sh -c \
  "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=$(printf %q "$TOK") vault write auth/kubernetes-apps/config \
    kubernetes_host=${HOST} \
    kubernetes_ca_cert=@/tmp/apps-ca.crt \
    token_reviewer_jwt=@/tmp/apps-reviewer.jwt \
    disable_iss_validation=true"

echo "=== host now ==="
docker exec "$NODE" crictl exec "$CID" sh -c \
  "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=$(printf %q "$TOK") vault read -field=kubernetes_host auth/kubernetes-apps/config"

SA_JWT=$(kubectl -n am-apps-prod create token am-backend-sa --duration=10m)
printf '%s' "$SA_JWT" | docker exec -i "$NODE" crictl exec -i "$CID" sh -c 'cat > /tmp/sa.jwt'
echo "=== login ==="
if docker exec "$NODE" crictl exec "$CID" sh -c \
  "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=$(printf %q "$TOK") vault write auth/kubernetes-apps/login role=am-backend-role jwt=@/tmp/sa.jwt" \
  >/tmp/login.out 2>/tmp/login.err; then
  echo LOGIN_OK
  grep -E 'token_policies|policies' /tmp/login.out | head -5 || true
else
  echo LOGIN_FAIL
  cat /tmp/login.err
  exit 1
fi
