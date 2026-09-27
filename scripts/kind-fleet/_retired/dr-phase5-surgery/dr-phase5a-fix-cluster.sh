#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export AM_OPS_REAL_KIND=/usr/local/libexec/am-real/kind

APPS_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-dr-apps-control-plane | head -1)
echo "apps_cp_ip=$APPS_IP"

# Fresh kubeconfig with CA + client certs
kind get kubeconfig --name am-dr-apps > /tmp/kc-am-dr-apps.raw.yaml
# SoT for host/laptop: public IP + keep CA/certs (do NOT set insecure-skip)
python3 <<PY
import yaml
from pathlib import Path
kc = yaml.safe_load(Path("/tmp/kc-am-dr-apps.raw.yaml").read_text())
for c in kc["clusters"]:
    c["cluster"]["server"] = "https://129.121.128.131:6444"
    c["cluster"].pop("insecure-skip-tls-verify", None)
Path("/data/am-state/kubeconfig.am-dr-apps.yaml").write_text(yaml.safe_dump(kc))
Path("/home/am-ops/.asrax/kubeconfig.am-dr-apps.yaml").write_text(yaml.safe_dump(kc))
print("wrote host kubeconfigs; user keys=", list(kc["users"][0]["user"].keys()))
print("has ca=", "certificate-authority-data" in kc["clusters"][0]["cluster"])
PY
chmod 600 /data/am-state/kubeconfig.am-dr-apps.yaml /home/am-ops/.asrax/kubeconfig.am-dr-apps.yaml
chown am-ops:am-ops /home/am-ops/.asrax/kubeconfig.am-dr-apps.yaml

# Argo secret: docker IP :6443 + CA/client certs
python3 <<PY
import json, yaml
from pathlib import Path
kc = yaml.safe_load(Path("/tmp/kc-am-dr-apps.raw.yaml").read_text())
cluster = kc["clusters"][0]["cluster"]
user = kc["users"][0]["user"]
server = "https://$APPS_IP:6443"
config = {
  "tlsClientConfig": {
    "insecure": False,
    "caData": cluster["certificate-authority-data"],
    "certData": user["client-certificate-data"],
    "keyData": user["client-key-data"],
  }
}
secret = {
  "apiVersion": "v1",
  "kind": "Secret",
  "metadata": {
    "name": "cluster-am-dr-apps",
    "namespace": "argocd",
    "labels": {"argocd.argoproj.io/secret-type": "cluster"},
  },
  "type": "Opaque",
  "stringData": {
    "name": "am-dr-apps",
    "server": server,
    "config": json.dumps(config),
  },
}
Path("/tmp/cluster-am-dr-apps.yaml").write_text(yaml.safe_dump(secret))
print("argo server", server)
PY

export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml
kubectl apply -f /tmp/cluster-am-dr-apps.yaml
kubectl -n argocd delete pod -l app.kubernetes.io/name=argocd-application-controller --force --grace-period=0 2>/dev/null || true
kubectl -n argocd wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-application-controller --timeout=180s

PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
sleep 10
kubectl -n argocd exec deploy/argocd-server -- sh -c "argocd login localhost:8080 --username admin --password '$PASS' --plaintext --grpc-web >/dev/null && argocd cluster list --server localhost:8080 --plaintext --grpc-web" 2>&1 | head -20

# smoke host kubeconfig
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
kubectl get --raw=/version | head -c 120; echo
