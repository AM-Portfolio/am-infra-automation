#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
POD=$(kubectl get pods -n am-apps-dr -o name | grep market-data | head -1 | cut -d/ -f2)

echo "=== pod age / restarts / ready ==="
kubectl get pod -n am-apps-dr "$POD" -o wide
kubectl describe pod -n am-apps-dr "$POD" | sed -n '/Conditions:/,/Events:/p' | head -40
echo "=== events ==="
kubectl describe pod -n am-apps-dr "$POD" | sed -n '/Events:/,$p' | tail -25

echo "=== env Influx / Upstox / Zerodha (redacted) ==="
kubectl exec -n am-apps-dr "$POD" -- sh -c '
  for v in INFLUXDB_URL INFLUX_URL SPRING_INFLUXDB_URL INFLUXDB_HOST INFLUXDB_ORG INFLUXDB_BUCKET \
           UPSTOCK_ACCESS_TOKEN UPSTOX_ACCESS_TOKEN UPSTOX_API_KEY JWT_SECRET_KEY \
           ZERODHA_ACCESS_TOKEN KITE_ACCESS_TOKEN; do
    val=$(printenv "$v" 2>/dev/null || true)
    if [ -n "$val" ]; then
      echo "$v=${val:0:12}...len=${#val}"
    fi
  done
  printenv | grep -iE "influx|upstox|upstock|zerodha|kite" | sed "s/=.*/=***/" | sort
'

echo "=== started? ==="
kubectl logs -n am-apps-dr "$POD" 2>&1 | grep -iE "Started Market|Tomcat started|Application run failed|GapFill|gap.fill|ready" | tail -30

echo "=== vault market-data keys (infra vault) ==="
python3 <<'PY'
import json,urllib.request,ssl
ctx=ssl._create_unverified_context()
cfg=json.load(open("/data/am-state/vault-dr-infra.json"))
# try apps vault token from terraform state or known path
import os,glob
tok=None
for p in ["/data/am-state/vault-dr-apps.json","/opt/am-infra-automation/terraform/kind-fleet/dr/vault-apps/terraform.tfstate"]:
  if os.path.exists(p):
    print("found", p)
# list CSI secret mount
print("done scan")
PY
ls /data/am-state/vault-dr*.json 2>/dev/null
# find vault apps token
ls /opt/am-infra-automation/terraform/kind-fleet/dr/vault-apps/*.tfvars /opt/am-infra-automation/terraform/kind-fleet/dr/vault-apps/.terraform* 2>/dev/null | head
