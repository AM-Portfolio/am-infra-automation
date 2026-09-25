#!/bin/bash
set -euo pipefail
export PYTHONUNBUFFERED=1
pkill -f 'wave_4g_sync.py' 2>/dev/null || true
sleep 1

# Ensure gitops copy has latest fin-agent yaml
mkdir -p /tmp/gitops-prod/agents
cp -f /tmp/am-fin-agent.yaml /tmp/gitops-prod/agents/am-fin-agent.yaml

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
    patch={"operation":{"initiatedBy":{"username":"admin"},"info":[{"name":"reason","value":"fix-fin-agent-vault-keys"}],"sync":{"prune":False,"syncStrategy":{"hook":{}}}}}
    subprocess.run(["kubectl","-n","argocd","patch","application",name,"--type","merge","--patch",json.dumps(patch)], check=True)
    print("synced", name, flush=True)

apply("am-fin-agent-prod","/tmp/gitops-prod/agents/am-fin-agent.yaml")
PY

export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
sleep 5
kubectl -n am-agents-prod delete pod -l app.kubernetes.io/instance=am-fin-agent-prod --force --grace-period=0 2>/dev/null || true

for i in $(seq 1 40); do
  echo "=== wait i=$i ==="
  kubectl -n am-agents-prod get pods -l app.kubernetes.io/instance=am-fin-agent-prod -o wide
  objs=$(kubectl -n am-agents-prod get secretproviderclass am-fin-agent-prod-vault-secrets -o jsonpath='{.spec.parameters.objects}' || true)
  echo "$objs" | grep -oE 'secretKey: "[^"]+"|secretPath: "[^"]+"' | sort -u
  if echo "$objs" | grep -q 'AM_FIN_AGENT_CLIENT_SECRET'; then
    echo "WARN: CLIENT_SECRET still in SPC"
  fi
  if echo "$objs" | grep -q 'secret/data'; then
    echo "WARN: secret/data still in SPC"
  fi
  ready=$(kubectl -n am-agents-prod get deploy am-fin-agent-prod -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  echo "ready=$ready"
  if [ "${ready:-0}" = "1" ]; then
    echo FIN_AGENT_FIX_OK
    exit 0
  fi
  pod=$(kubectl -n am-agents-prod get pods -l app.kubernetes.io/instance=am-fin-agent-prod -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$pod" ]; then
    kubectl -n am-agents-prod describe pod "$pod" 2>/dev/null | grep FailedMount | tail -3 || true
  fi
  sleep 8
done
echo FIN_AGENT_FIX_TIMEOUT
exit 1
