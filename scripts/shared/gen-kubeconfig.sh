#!/bin/bash
set -e
echo "[1/4] Creating serviceaccount..."
docker exec am-preprod-control-plane kubectl create serviceaccount am-admin -n kube-system --kubeconfig /etc/kubernetes/admin.conf 2>/dev/null || true
docker exec am-preprod-control-plane kubectl create clusterrolebinding am-admin-binding --clusterrole=cluster-admin --serviceaccount=kube-system:am-admin --kubeconfig /etc/kubernetes/admin.conf 2>/dev/null || true

echo "[2/4] Creating token..."
TOKEN=$(docker exec am-preprod-control-plane kubectl create token am-admin -n kube-system --duration=24h --kubeconfig /etc/kubernetes/admin.conf)

echo "[3/4] Writing kubeconfig to /data/am-state/am-preprod-config..."
mkdir -p /data/am-state
cat > /data/am-state/am-preprod-config << KUBECONFIG
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://127.0.0.1:6443
    insecure-skip-tls-verify: true
  name: kind-am-preprod
contexts:
- context:
    cluster: kind-am-preprod
    user: am-admin
  name: kind-am-preprod
current-context: kind-am-preprod
users:
- name: am-admin
  user:
    token: ${TOKEN}
KUBECONFIG

echo "[4/4] Verifying..."
kubectl --kubeconfig /data/am-state/am-preprod-config get nodes
echo "KUBECONFIG_OK"
