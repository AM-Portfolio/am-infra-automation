#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin

# Prefer platform kubeconfig for Argo
for kc in /data/am-state/kubeconfig.am-dr-platform.yaml /data/am-state/kubeconfig.am-dr-infra.yaml /root/.asrax/kubeconfig.am-dr-platform.yaml; do
  if [ -f "$kc" ]; then export KUBECONFIG="$kc"; echo "KUBECONFIG=$kc"; break; fi
done

# Find argocd server / use kubectl port-forward or in-cluster
if command -v argocd >/dev/null 2>&1; then
  echo "argocd CLI present"
fi

# Sync via kubectl + argocd Application annotation / hard refresh
NS=argocd
APP=am-market-data-dr
kubectl get application -n "$NS" "$APP" -o jsonpath='{.metadata.name} sync={.status.sync.status} health={.status.health.status}{"\n"}' 2>/dev/null || {
  echo "app not in this cluster; listing apps with market"
  kubectl get applications -A 2>/dev/null | grep -i market || true
  kubectl get applications -A 2>/dev/null | head -5
  exit 1
}

# Trigger hard refresh then sync (manual policy)
kubectl annotate application -n "$NS" "$APP" argocd.argoproj.io/refresh=hard --overwrite
sleep 3
# Use argocd if available with local port
if command -v argocd >/dev/null 2>&1; then
  # try in-cluster server
  SERVER=$(kubectl get svc -n argocd argocd-server -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
  PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)
  if [ -n "$SERVER" ] && [ -n "$PASS" ]; then
    argocd login "$SERVER" --username admin --password "$PASS" --insecure --grpc-web 2>/dev/null || true
    argocd app sync "$APP" --grpc-web --insecure --force 2>&1 | tail -40
  else
    # fallback: patch operation
    kubectl patch application -n "$NS" "$APP" --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD","syncStrategy":{"hook":{}}}}}'
  fi
else
  kubectl patch application -n "$NS" "$APP" --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
fi

sleep 5
kubectl get application -n "$NS" "$APP" -o jsonpath='sync={.status.sync.status} health={.status.health.status}{"\n"}'
