#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin

python3 <<'PY'
import json, ssl, urllib.request

tok = json.load(open("/data/am-state/vault-dr-infra.json"))["root_token"]
ctx = ssl._create_unverified_context()
addr = "https://vault-dr.asrax.in"
headers = {"X-Vault-Token": tok, "User-Agent": "am-kind-fleet-gates/1"}

def get(path):
    req = urllib.request.Request(f"{addr}/v1/{path}", headers=headers)
    with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
        return ((json.loads(r.read().decode()).get("data") or {}).get("data") or {})

d = get("apps/data/dr/services/am-market-data")
keys = sorted(d.keys())
print("dr market-data keys:", keys)
for k in ("UPSTOCK_ACCESS_TOKEN", "UPSTOX_ACCESS_TOKEN", "UPSTOX_API_KEY", "JWT_SECRET_KEY"):
    if k in d:
        v = str(d[k])
        print(f"  {k}: len={len(v)} placeholder={v.startswith('dr-fleet') or 'fleet' in v.lower() or v in ('changeme','placeholder')}")
        print(f"  {k}_prefix={v[:24]!r}")
PY

export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
POD=$(kubectl get pods -n am-apps-dr -o name | grep market-data | head -1 | cut -d/ -f2)
echo "=== actuator health ==="
kubectl exec -n am-apps-dr "$POD" -- curl -sS -m 8 http://127.0.0.1:8080/actuator/health 2>&1 | python3 -c 'import sys,json; t=sys.stdin.read();
try:
 d=json.loads(t); print("status", d.get("status"));
 comps=d.get("components") or {};
 for k,v in sorted(comps.items()):
  print(f"  {k}: {v.get(\"status\")}")
except Exception:
 print(t[:800])'
