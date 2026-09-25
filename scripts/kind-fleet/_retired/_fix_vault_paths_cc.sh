#!/bin/bash
set -euo pipefail
export PYTHONUNBUFFERED=1
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-platform.yaml

python3 - <<'PY'
import json, subprocess, yaml
from pathlib import Path

def apply(name, path):
    desired = yaml.safe_load(Path(path).read_text())
    app = json.loads(subprocess.check_output(["kubectl","-n","argocd","get","app",name,"-o","json"]))
    for k in ("sources","project","destination","syncPolicy","ignoreDifferences"):
        if k in desired.get("spec",{}):
            app["spec"][k] = desired["spec"][k]
    helm = app["spec"]["sources"][0].get("helm") or {}
    if "values" in helm and isinstance(helm["values"], str):
        helm["values"] = helm["values"].replace("\u2014","-").replace("\u2013","-")
        yaml.safe_load(helm["values"])
        app["spec"]["sources"][0]["helm"] = helm
    out = Path(f"/tmp/{name}-merged.json")
    out.write_text(json.dumps(app))
    subprocess.run(["kubectl","-n","argocd","replace","-f",str(out)], check=True)
    print("applied", name, flush=True)
    patch = {"operation":{"initiatedBy":{"username":"admin"},"info":[{"name":"reason","value":"fix-vault-apps-path"}],"sync":{"prune":False,"syncStrategy":{"hook":{}}}}}
    subprocess.run(["kubectl","-n","argocd","patch","application",name,"--type","merge","--patch",json.dumps(patch)], check=True)
    print("synced", name, flush=True)

for name, rel in [
    ("am-notification-prod","apps/am-notification.yaml"),
    ("am-subscription-prod","apps/am-subscription.yaml"),
    ("am-user-platform-prod","apps/am-user-platform.yaml"),
]:
    apply(name, f"/tmp/gitops-prod/{rel}")
PY

export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
# drop stuck pods so new RS can progress after SPC rewrite
kubectl -n am-apps-prod delete pod am-notification-prod-5cbdb8b967-xrbpr am-subscription-prod-846b9667bb-rt5cn am-user-platform-prod-85cb8db9bd-rgk4h --force --grace-period=0 2>/dev/null || true

for i in $(seq 1 48); do
  echo "=== wait i=$i ==="
  kubectl -n am-apps-prod get pods -l 'app.kubernetes.io/instance in (am-notification-prod,am-subscription-prod,am-user-platform-prod)' -o wide
  # check SPC no longer has secret/data for identity
  bad=$(kubectl -n am-apps-prod get secretproviderclass am-user-platform-prod-vault-secrets -o jsonpath='{.spec.parameters.objects}' | grep -c 'secret/data' || true)
  echo "user-platform secret/data count=$bad"
  n=$(kubectl -n am-apps-prod get deploy am-notification-prod -o jsonpath='{.status.readyReplicas}')
  s=$(kubectl -n am-apps-prod get deploy am-subscription-prod -o jsonpath='{.status.readyReplicas}')
  u=$(kubectl -n am-apps-prod get deploy am-user-platform-prod -o jsonpath='{.status.readyReplicas}')
  echo "ready n=$n s=$s u=$u"
  if [ "${n:-0}" = "1" ] && [ "${s:-0}" = "1" ] && [ "${u:-0}" = "1" ] && [ "$bad" = "0" ]; then
    echo FIX_CC_OK
    exit 0
  fi
  sleep 10
done
echo FIX_CC_TIMEOUT
exit 1
