#!/bin/bash
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-platform.yaml
APP=am-market-data-prod

PASSFILE=/tmp/argo-pw.txt
if [ ! -f "$PASSFILE" ] || [ ! -s "$PASSFILE" ]; then
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d > "$PASSFILE" || true
fi
# Prefer saved admin pw from phase 3 if initial-admin rotated
if [ -f /tmp/argo-pw.txt ] && [ -s /tmp/argo-pw.txt ]; then
  PASSFILE=/tmp/argo-pw.txt
fi
test -s "$PASSFILE"

IMG=$(kubectl -n argocd get deploy argocd-server -o jsonpath='{.spec.template.spec.containers[0].image}')
kubectl -n argocd delete pod argo-sync-4e --ignore-not-found
kubectl -n argocd delete secret argo-probe-pw --ignore-not-found
kubectl -n argocd create secret generic argo-probe-pw --from-file=password="$PASSFILE"

APP="$APP" IMG="$IMG" python3 - <<'PY'
import os
img=os.environ["IMG"]
app=os.environ["APP"]
# Non-interactive: --plaintext avoids TLS y/n prompt against in-cluster http service
open("/tmp/argo-sync-4e.yaml","w").write(f"""apiVersion: v1
kind: Pod
metadata:
  name: argo-sync-4e
  namespace: argocd
spec:
  restartPolicy: Never
  containers:
  - name: sync
    image: {img}
    env:
    - name: ARGO_PASS
      valueFrom:
        secretKeyRef:
          name: argo-probe-pw
          key: password
    command: ["sh","-c"]
    args:
      - |
        set -e
        yes | argocd login argocd-server.argocd.svc:80 --plaintext --grpc-web --username admin --password "$ARGO_PASS" \\
          || yes | argocd login argocd-server.argocd.svc:443 --insecure --grpc-web --username admin --password "$ARGO_PASS"
        argocd app sync {app} --prune=false --timeout 300
        argocd app get {app}
        echo WAVE4E_SYNC_DONE
""")
print("wrote", app, img)
PY

kubectl -n argocd apply -f /tmp/argo-sync-4e.yaml
for i in $(seq 1 60); do
  if kubectl -n argocd logs argo-sync-4e 2>/dev/null | grep -q WAVE4E_SYNC_DONE; then
    echo SYNC_OK
    break
  fi
  st=$(kubectl -n argocd get pod argo-sync-4e -o jsonpath='{.status.phase}' 2>/dev/null || echo Missing)
  echo "wait sync pod=$st i=$i"
  if [ "$st" = "Failed" ] || [ "$st" = "Succeeded" ]; then
    kubectl -n argocd logs argo-sync-4e 2>&1 | tail -80
    break
  fi
  sleep 5
done
kubectl -n argocd logs argo-sync-4e 2>&1 | tail -100 || true
kubectl -n argocd get application "$APP" -o wide || true
kubectl -n argocd delete pod argo-sync-4e --ignore-not-found
kubectl -n argocd delete secret argo-probe-pw --ignore-not-found

# If still OutOfSync/Missing, fall back to Argo API sync via curl from a pod
SYNC=$(kubectl -n argocd get application "$APP" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo Unknown)
HEALTH=$(kubectl -n argocd get application "$APP" -o jsonpath='{.status.health.status}' 2>/dev/null || echo Unknown)
echo "post_sync sync=$SYNC health=$HEALTH"
if [ "$SYNC" != "Synced" ]; then
  echo "FALLBACK_KUBECTL_SYNC"
  # Patch operation onto Application CR (no CLI TLS prompt)
  kubectl -n argocd patch application "$APP" --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"prune":false,"syncStrategy":{"hook":{}}}}}'
  for i in $(seq 1 36); do
    SYNC=$(kubectl -n argocd get application "$APP" -o jsonpath='{.status.sync.status}')
    HEALTH=$(kubectl -n argocd get application "$APP" -o jsonpath='{.status.health.status}')
    PHASE=$(kubectl -n argocd get application "$APP" -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true)
    echo "op i=$i sync=$SYNC health=$HEALTH phase=$PHASE"
    if [ "$SYNC" = "Synced" ]; then break; fi
    sleep 5
  done
fi

bash /tmp/wave_4e_market.sh
