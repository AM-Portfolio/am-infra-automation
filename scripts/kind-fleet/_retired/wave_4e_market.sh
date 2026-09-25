#!/bin/bash
# Phase 4e: wait market-data Ready + domain quote smoke (Bearer from Vault test user).
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
echo "=== pods ==="
for i in $(seq 1 36); do
  kubectl -n am-apps-prod get pods -l app.kubernetes.io/instance=am-market-data-prod -o wide 2>/dev/null || kubectl -n am-apps-prod get pods | grep -i market || true
  ready=$(kubectl -n am-apps-prod get deploy am-market-data-prod -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  ready=${ready:-0}
  echo "readyReplicas=$ready attempt=$i"
  if [ "$ready" -ge 1 ]; then break; fi
  # show events for failing pods
  for p in $(kubectl -n am-apps-prod get pods -o name 2>/dev/null | grep market-data | head -3); do
    kubectl -n am-apps-prod describe "$p" 2>/dev/null | grep -A3 -E 'Warning|Failed|Error|Image|Mount' | tail -20 || true
  done
  sleep 10
done
kubectl -n am-apps-prod get deploy,pods,ingress -l app.kubernetes.io/instance=am-market-data-prod 2>/dev/null || true
kubectl -n am-apps-prod get deploy am-market-data-prod -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}' 2>/dev/null || true

# hostAliases + Traefik strip-prefix are TF/gitops SoT — no kubectl patch here.
kubectl -n am-apps-prod get secret ghcr-creds >/dev/null 2>&1 || echo "WARN missing ghcr-creds"

python3 <<'PY'
import json,urllib.request,urllib.parse,urllib.error,ssl,base64,subprocess,os
os.environ["KUBECONFIG"]="/data/am-state/kubeconfig.am-prod-platform.yaml"
ctx=ssl._create_unverified_context()
UA={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}

# token via modern-ui
KC_IP=subprocess.check_output(["docker","inspect","-f","{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}","am-prod-platform-control-plane"],text=True).strip().split()[0]
KC=f"http://{KC_IP}:30808"
A=open("/tmp/pw-am-admin-test.txt").read().strip()
ADMIN_PASS=base64.b64decode(subprocess.check_output(["kubectl","-n","identity","get","secret","keycloak-admin","-o","jsonpath={.data.password}"],text=True)).decode()

def post(url,data,ctx=None):
  h={"Content-Type":"application/x-www-form-urlencoded",**UA}
  req=urllib.request.Request(url,data=urllib.parse.urlencode(data).encode(),headers=h)
  with urllib.request.urlopen(req,context=ctx,timeout=30) as r: return json.load(r)

atok=post(f"{KC}/realms/master/protocol/openid-connect/token",{"client_id":"admin-cli","username":"admin","password":ADMIN_PASS,"grant_type":"password"})["access_token"]
req=urllib.request.Request(f"{KC}/admin/realms/am-realm/clients?clientId=am-modern-ui",headers={"Authorization":"Bearer "+atok})
with urllib.request.urlopen(req,timeout=30) as r: clients=json.load(r)
cid=clients[0]["id"]
req=urllib.request.Request(f"{KC}/admin/realms/am-realm/clients/{cid}/client-secret",headers={"Authorization":"Bearer "+atok})
with urllib.request.urlopen(req,timeout=30) as r: secret=json.load(r)["value"]
d=post("https://auth.asrax.in/realms/am-realm/protocol/openid-connect/token",{"client_id":"am-modern-ui","client_secret":secret,"username":"am-admin-test","password":A,"grant_type":"password","scope":"openid profile email"},ctx=ctx)
tok=d["access_token"]
print("token_ok", len(tok))

paths=[
  "https://am.asrax.in/market/actuator/health",
  "https://am.asrax.in/market/v1/market-data/quotes?symbol=RELIANCE",
  "https://am.asrax.in/market/v1/market-data/quotes?symbols=RELIANCE",
  "https://am.asrax.in/market/v1/market-data/live-ltp?symbol=RELIANCE",
  "https://am.asrax.in/gateway/market/v1/market-data/quotes?symbol=RELIANCE",
]
for url in paths:
  for use_auth in (False, True):
    h=dict(UA)
    if use_auth: h["Authorization"]="Bearer "+tok
    req=urllib.request.Request(url,headers=h)
    try:
      with urllib.request.urlopen(req,context=ctx,timeout=45) as r:
        print(("AUTH" if use_auth else "ANON"), r.status, url, r.read()[:180])
    except urllib.error.HTTPError as e:
      print(("AUTH" if use_auth else "ANON"), e.code, url, e.read()[:180])
    except Exception as e:
      print(("AUTH" if use_auth else "ANON"), "ERR", url, e)
print("4E_SMOKE_DONE")
PY
