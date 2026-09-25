#!/bin/bash
set -euo pipefail
export PYTHONUNBUFFERED=1
cp -f /tmp/am-support-agent.yaml /tmp/gitops-prod/agents/am-support-agent.yaml
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-platform.yaml
python3 - <<'PY'
import json, subprocess, yaml
from pathlib import Path

def apply(name, path):
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
    print("applied", name, flush=True)
    patch={"operation":{"initiatedBy":{"username":"admin"},"info":[{"name":"reason","value":"fix-temporal-nodeport"}],"sync":{"prune":False,"syncStrategy":{"hook":{}}}}}
    subprocess.run(["kubectl","-n","argocd","patch","application",name,"--type","merge","--patch",json.dumps(patch)], check=True)
    print("synced", name, flush=True)

apply("am-support-agent-prod","/tmp/gitops-prod/agents/am-support-agent.yaml")
PY

export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
sleep 8
kubectl -n am-agents-prod delete pod -l app.kubernetes.io/component=worker,app.kubernetes.io/instance=am-support-agent-prod --force --grace-period=0 2>/dev/null || true

for i in $(seq 1 36); do
  echo "=== wait i=$i ==="
  kubectl -n am-agents-prod get pods -l 'app.kubernetes.io/instance=am-support-agent-prod' -o wide
  ready=$(kubectl -n am-agents-prod get deploy am-support-agent-worker -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  echo "worker_ready=$ready"
  # show TEMPORAL_HOST in pod env if running
  pod=$(kubectl -n am-agents-prod get pods -l app.kubernetes.io/component=worker,app.kubernetes.io/instance=am-support-agent-prod -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$pod" ]; then
    kubectl -n am-agents-prod get pod "$pod" -o jsonpath='{.spec.containers[0].env[?(@.name=="TEMPORAL_HOST")].value}' 2>/dev/null; echo
    kubectl -n am-agents-prod logs "$pod" --tail=15 2>&1 | grep -vE 'password|secret|token' || true
  fi
  if [ "${ready:-0}" = "1" ]; then
    echo SUPPORT_WORKER_FIX_OK
    exit 0
  fi
  sleep 8
done
echo SUPPORT_WORKER_FIX_TIMEOUT
exit 1
