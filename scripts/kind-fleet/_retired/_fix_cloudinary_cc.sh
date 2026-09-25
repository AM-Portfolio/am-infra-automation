#!/bin/bash
set -euo pipefail
export PYTHONUNBUFFERED=1
pkill -f 'wave_4g_sync.py' 2>/dev/null || true
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-platform.yaml
python3 - <<'PY'
import json, subprocess, yaml
from pathlib import Path
name="am-cloudinary-manager-prod"
path="/tmp/gitops-prod/apps/am-cloudinary-manager.yaml"
desired=yaml.safe_load(Path(path).read_text())
app=json.loads(subprocess.check_output(["kubectl","-n","argocd","get","app",name,"-o","json"]))
for k in ("sources","project","destination","syncPolicy","ignoreDifferences"):
    if k in desired.get("spec",{}):
        app["spec"][k]=desired["spec"][k]
helm=app["spec"]["sources"][0].get("helm") or {}
if "values" in helm and isinstance(helm["values"], str):
    helm["values"]=helm["values"].replace("\u2014","-").replace("\u2013","-")
    yaml.safe_load(helm["values"])
    app["spec"]["sources"][0]["helm"]=helm
out=Path(f"/tmp/{name}-merged.json")
out.write_text(json.dumps(app))
subprocess.run(["kubectl","-n","argocd","replace","-f",str(out)], check=True)
print("applied", flush=True)
patch={"operation":{"initiatedBy":{"username":"admin"},"info":[{"name":"reason","value":"fix-cloudinary-path"}],"sync":{"prune":False,"syncStrategy":{"hook":{}}}}}
subprocess.run(["kubectl","-n","argocd","patch","application",name,"--type","merge","--patch",json.dumps(patch)], check=True)
print("synced", flush=True)
PY
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
sleep 5
kubectl -n am-apps-prod delete pod -l app.kubernetes.io/instance=am-cloudinary-manager-prod --force --grace-period=0 2>/dev/null || true
for i in $(seq 1 36); do
  kubectl -n am-apps-prod get pods -l app.kubernetes.io/instance=am-cloudinary-manager-prod -o wide
  objs=$(kubectl -n am-apps-prod get secretproviderclass am-cloudinary-manager-prod-vault-secrets -o jsonpath='{.spec.parameters.objects}' || true)
  echo "$objs" | grep -o 'secretPath: "[^"]*"' | sort -u
  ready=$(kubectl -n am-apps-prod get deploy am-cloudinary-manager-prod -o jsonpath='{.status.readyReplicas}')
  echo "ready=$ready i=$i"
  if [ "${ready:-0}" = "1" ]; then
    echo CLOUDINARY_FIX_OK
    exit 0
  fi
  pod=$(kubectl -n am-apps-prod get pods -l app.kubernetes.io/instance=am-cloudinary-manager-prod -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$pod" ]; then
    kubectl -n am-apps-prod describe pod "$pod" 2>/dev/null | grep FailedMount | tail -2 || true
  fi
  sleep 8
done
echo CLOUDINARY_FIX_TIMEOUT
exit 1
