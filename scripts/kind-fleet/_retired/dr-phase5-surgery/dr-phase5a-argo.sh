#!/usr/bin/env bash
# Phase 5a: register am-dr-apps in DR Argo + apply AppProject + AppSets (enroll only).
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml

ARGO_NS=argocd
APPS_KC=/data/am-state/kubeconfig.am-dr-apps.yaml
CLUSTER_NAME=am-dr-apps
# Public API for Argo (platform pod) → VPS IP:6444 (cert SAN)
APPS_SERVER=https://129.121.128.131:6444

echo "=== argocd pods ==="
kubectl -n "$ARGO_NS" get pods | head -20

# Ensure AppProject
if [[ -f /opt/am-gitops/projects/am-dr.yaml ]]; then
  kubectl apply -f /opt/am-gitops/projects/am-dr.yaml
elif [[ -f /opt/am-infra-automation/../am-gitops/projects/am-dr.yaml ]]; then
  kubectl apply -f /opt/am-infra-automation/../am-gitops/projects/am-dr.yaml
else
  echo "WARN: am-dr.yaml not on host — will apply from stdin if synced"
fi

# Extract bearer token for am-dr-apps via SA used by Argo cluster secret pattern
# Prefer argocd cluster add if CLI present in argocd-server
if kubectl -n "$ARGO_NS" get secret -l argocd.argoproj.io/secret-type=cluster -o name 2>/dev/null | grep -q am-dr-apps; then
  echo "cluster secret am-dr-apps already present"
else
  echo "=== creating Argo cluster secret for $CLUSTER_NAME ==="
  # Create a long-lived SA in apps cluster for Argo
  export KUBECONFIG_APPS=$APPS_KC
  KUBECONFIG=$APPS_KC kubectl get ns argocd-manager 2>/dev/null || true
  # Standard approach: use argocd CLI from a temporary pod or host
  if command -v argocd >/dev/null 2>&1; then
    ARGO_PASS=$(kubectl -n "$ARGO_NS" get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)
    if [[ -z "$ARGO_PASS" ]]; then
      # platform TF may store password elsewhere
      ARGO_PASS=$(cd /opt/am-infra-automation/terraform/kind-fleet/dr/platform && terraform output -raw argocd_admin_password 2>/dev/null || true)
    fi
    argocd login argocd-dr.asrax.in --username admin --password "$ARGO_PASS" --grpc-web || \
      argocd login argocd-server.argocd.svc --username admin --password "$ARGO_PASS" --grpc-web --insecure || true
    KUBECONFIG=$APPS_KC argocd cluster add kind-am-dr-apps --name "$CLUSTER_NAME" --yes --upsert || \
      KUBECONFIG=$APPS_KC argocd cluster add kind-am-dr-apps --name "$CLUSTER_NAME" --yes
  else
    echo "no argocd CLI — writing cluster secret via kubeconfig"
    python3 <<'PY'
import base64, json, yaml, subprocess, os
from pathlib import Path

kc_path = Path("/data/am-state/kubeconfig.am-dr-apps.yaml")
kc = yaml.safe_load(kc_path.read_text())
cluster = kc["clusters"][0]["cluster"]
user = kc["users"][0]["user"]
# Prefer client cert; else token
ca = cluster.get("certificate-authority-data") or ""
server = "https://129.121.128.131:6444"
config = {
  "tlsClientConfig": {
    "insecure": False,
    "caData": ca,
  }
}
if "client-certificate-data" in user:
  config["tlsClientConfig"]["certData"] = user["client-certificate-data"]
  config["tlsClientConfig"]["keyData"] = user["client-key-data"]
elif "token" in user:
  config["bearerToken"] = user["token"]
else:
  raise SystemExit("kubeconfig has neither client cert nor token")

secret = {
  "apiVersion": "v1",
  "kind": "Secret",
  "metadata": {
    "name": "cluster-am-dr-apps",
    "namespace": "argocd",
    "labels": {
      "argocd.argoproj.io/secret-type": "cluster",
    },
  },
  "type": "Opaque",
  "stringData": {
    "name": "am-dr-apps",
    "server": server,
    "config": json.dumps(config),
  },
}
Path("/tmp/cluster-am-dr-apps.yaml").write_text(yaml.dump(secret))
print("wrote /tmp/cluster-am-dr-apps.yaml server=", server)
PY
    kubectl apply -f /tmp/cluster-am-dr-apps.yaml
  fi
fi

export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml
echo "=== registered clusters ==="
kubectl -n "$ARGO_NS" get secret -l argocd.argoproj.io/secret-type=cluster -o custom-columns=NAME:.metadata.name,SERVER:.data.server --no-headers 2>/dev/null | while read n s; do
  echo "$n $(echo "$s" | base64 -d 2>/dev/null || true)"
done

# Apply AppSets if gitops present
for f in apps-dr-fleet agents-dr-fleet; do
  p="/opt/am-gitops/application-sets/${f}.yaml"
  if [[ -f "$p" ]]; then
    echo "apply $p"
    kubectl apply -f "$p"
  else
    echo "MISSING $p"
  fi
done

echo "=== applications (dr) ==="
kubectl -n "$ARGO_NS" get applications -l 'am.asrax.in/fleet=dr' 2>/dev/null | head -40 || \
  kubectl -n "$ARGO_NS" get applications 2>/dev/null | grep -i dr | head -40 || true
kubectl -n "$ARGO_NS" get applicationsets 2>/dev/null | grep -i dr || true

echo "PHASE5A_DONE"
