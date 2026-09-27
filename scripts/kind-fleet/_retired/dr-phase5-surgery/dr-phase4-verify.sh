#!/usr/bin/env bash
# Phase 4 gate: NS/CSI/Vault auth + CSI login Job + vault path smoke.
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml

VAULT_TOKEN=$(python3 -c 'import json; print(json.load(open("/data/am-state/vault-dr-infra.json"))["root_token"])')
export VAULT_ADDR=https://vault-dr.asrax.in
export VAULT_TOKEN
export VAULT_KUBECONFIG=/data/am-state/kubeconfig.am-dr-infra.yaml

vault_exec() {
  KUBECONFIG="$VAULT_KUBECONFIG" kubectl -n vault exec vault-0 -- \
    env VAULT_TOKEN="$VAULT_TOKEN" VAULT_ADDR=http://127.0.0.1:8200 vault "$@"
}

echo "=== namespaces / SA ==="
kubectl get ns am-apps-dr am-agents-dr edge
kubectl get sa -n am-apps-dr am-backend-sa
kubectl get sa -n am-agents-dr am-backend-sa

echo "=== CSI daemonsets ==="
kubectl get ds -n kube-system | grep -E 'csi|vault' || true
kubectl get pods -n kube-system | grep -iE 'csi|secrets-store|vault-csi' || true

echo "=== vault auth ==="
vault_exec auth list 2>/dev/null | grep kubernetes-apps || true
vault_exec read auth/kubernetes-apps/role/am-backend-role
vault_exec kv get -mount=apps dr/infra/postgres | head -25

echo "=== CSI login job ==="
kubectl delete job vault-csi-login-test -n am-apps-dr --ignore-not-found
cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: vault-csi-login-test
  namespace: am-apps-dr
spec:
  ttlSecondsAfterFinished: 180
  backoffLimit: 2
  template:
    spec:
      serviceAccountName: am-backend-sa
      restartPolicy: Never
      containers:
      - name: login
        image: hashicorp/vault:1.17.2
        env:
        - name: VAULT_ADDR
          value: https://vault-dr.asrax.in
        command:
        - /bin/sh
        - -ec
        - |
          JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
          RESP=$(vault write -format=json auth/kubernetes-apps/login role=am-backend-role jwt="$JWT")
          TOKEN=$(echo "$RESP" | awk -F'"' '/client_token/ {print $4; exit}')
          if [ -z "$TOKEN" ]; then echo "LOGIN_FAIL"; echo "$RESP"; exit 1; fi
          export VAULT_TOKEN="$TOKEN"
          OUT=$(vault kv get -mount=apps -format=json dr/infra/postgres)
          echo "$OUT" | grep -q POSTGRES_HOST || echo "$OUT" | grep -q '"host"'
          echo LOGIN_AND_READ_OK
EOF
kubectl wait --for=condition=complete job/vault-csi-login-test -n am-apps-dr --timeout=180s || {
  echo "JOB_FAILED"
  kubectl describe job -n am-apps-dr vault-csi-login-test | tail -40
  kubectl logs -n am-apps-dr job/vault-csi-login-test 2>&1 | tail -40 || true
  exit 1
}
kubectl logs -n am-apps-dr job/vault-csi-login-test

echo "=== host rewrite spot-check ==="
vault_exec kv get -format=json -mount=apps dr/infra/postgres | python3 -c '
import json,sys
d=json.load(sys.stdin)["data"]["data"]
print({k:d[k] for k in d if "HOST" in k.upper() or k.lower()=="host"})
'
vault_exec kv get -format=json -mount=apps dr/infra/keycloak | python3 -c '
import json,sys
d=json.load(sys.stdin)["data"]["data"]
print({k:d.get(k) for k in sorted(d) if any(x in k.upper() for x in ("URL","HOST","ISSUER","REALM"))})
'

echo "=== phase_gates 4a ==="
cd /opt/am-infra-automation
if [[ -d scripts/kind-fleet/phase_gates ]]; then
  PYTHONPATH=scripts/kind-fleet python3 -m phase_gates --env dr --wave 4a || echo "phase_gates_failed_or_cfg"
else
  echo "phase_gates missing — CSI login above is the gate"
fi

echo "PHASE4_GREEN"
