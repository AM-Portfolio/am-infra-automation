#!/bin/bash
set -euo pipefail
export PYTHONUNBUFFERED=1
pkill -f 'wave_4g_sync.py' 2>/dev/null || true
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
    patch={"operation":{"initiatedBy":{"username":"admin"},"info":[{"name":"reason","value":"fix-mcp-gateway-path"}],"sync":{"prune":False,"syncStrategy":{"hook":{}}}}}
    subprocess.run(["kubectl","-n","argocd","patch","application",name,"--type","merge","--patch",json.dumps(patch)], check=True)
    print("synced", name, flush=True)

apply("am-tool-agent-prod","/tmp/gitops-prod/agents/am-tool-agent.yaml")
apply("am-db-agent-prod","/tmp/gitops-prod/agents/am-db-agent.yaml")
PY
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
sleep 5
kubectl -n am-agents-prod delete pod -l app.kubernetes.io/instance=am-tool-agent-prod --force --grace-period=0 2>/dev/null || true
for i in $(seq 1 36); do
  kubectl -n am-agents-prod get pods -l app.kubernetes.io/instance=am-tool-agent-prod -o wide
  objs=$(kubectl -n am-agents-prod get secretproviderclass am-tool-agent-prod-vault-secrets -o jsonpath='{.spec.parameters.objects}' || true)
  echo "$objs" | grep -o 'secretPath: "[^"]*"' | sort -u
  ready=$(kubectl -n am-agents-prod get deploy am-tool-agent-prod -o jsonpath='{.status.readyReplicas}')
  echo "ready=$ready i=$i"
  if [ "${ready:-0}" = "1" ]; then
    echo TOOL_AGENT_FIX_OK
    exit 0
  fi
  pod=$(kubectl -n am-agents-prod get pods -l app.kubernetes.io/instance=am-tool-agent-prod -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$pod" ]; then
    kubectl -n am-agents-prod describe pod "$pod" 2>/dev/null | grep FailedMount | tail -2 || true
  fi
  sleep 8
done
echo TOOL_AGENT_FIX_TIMEOUT
exit 1
