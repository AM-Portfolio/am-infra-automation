#!/usr/bin/env bash
# Phase 5c prep: apps-edge Traefik NodePort 30080 + middlewares TF + sync wave.
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml

echo "=== install Traefik on apps edge (NodePort 30080) ==="
helm repo add traefik https://traefik.github.io/charts 2>/dev/null || true
helm repo update traefik
helm upgrade --install traefik traefik/traefik -n edge --create-namespace \
  --version 28.3.0 \
  --set ports.web.exposedPort=80 \
  --set ports.web.port=8000 \
  --set ports.web.nodePort=30080 \
  --set ports.websecure.exposedPort=443 \
  --set ports.websecure.port=8443 \
  --set ports.websecure.nodePort=30443 \
  --set service.type=NodePort \
  --set providers.kubernetesIngress.publishedService.enabled=true \
  --set providers.kubernetesCRD.enabled=true \
  --set ingressClass.enabled=true \
  --set ingressClass.isDefaultClass=true \
  --wait --timeout 300s

kubectl -n edge get pods,svc
kubectl -n edge get svc traefik -o wide

echo "=== terraform middlewares ==="
cd /opt/am-infra-automation/terraform/kind-fleet/dr/apps
terraform apply -auto-approve -input=false \
  -target=kubernetes_manifest.middleware_global_cors_apps \
  -target=kubernetes_manifest.middleware_strip_prefix_apps \
  -target=kubernetes_manifest.middleware_rewrite_am_document_singular \
  -target=kubernetes_manifest.middleware_global_cors_agents \
  -target=kubernetes_manifest.middleware_strip_prefix_agents \
  -target=kubernetes_manifest.middleware_strip_prefix_parser \
  2>&1 | tee /tmp/dr-middlewares.log | tail -40

export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
kubectl get middleware -A 2>&1 | head -20

echo "=== sync 5c ==="
bash /tmp/dr-phase5c-sync.sh
