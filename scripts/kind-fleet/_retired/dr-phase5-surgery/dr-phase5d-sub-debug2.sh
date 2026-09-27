#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml

POD=$(kubectl get pods -n am-apps-dr --sort-by=.metadata.creationTimestamp -o name | grep subscription | tail -1 | cut -d/ -f2)
echo "pod=$POD"
kubectl get pod -n am-apps-dr "$POD" -o json > /tmp/sub-pod.json
python3 - <<'PY'
import json
p=json.load(open("/tmp/sub-pod.json"))
for c in p["spec"]["containers"]:
  print("container", c["name"])
  print("envFrom", c.get("envFrom"))
  for e in c.get("env") or []:
    n=e.get("name","")
    if any(x in n.upper() for x in ("POSTGRES","DATABASE","DB_","SQL","LAGO","SSL","HOST")):
      if "value" in e:
        print(f"  {n}={e['value']!r}")
      elif "valueFrom" in e:
        vf=e["valueFrom"]
        print(f"  {n}=valueFrom:{list(vf.keys())[0]}")
print("hostAliases", p["spec"].get("hostAliases"))
print("volumes", [v.get("name") for v in p["spec"].get("volumes") or []])
print("ready", p["status"].get("containerStatuses"))
PY

echo "=== logs ==="
kubectl logs -n am-apps-dr "$POD" --tail=30 2>&1 | tail -30

echo "=== secret lens ==="
kubectl get secret -n am-apps-dr am-subscription-dr-synced-secrets -o json > /tmp/sub-sec.json
python3 - <<'PY'
import json,base64
s=json.load(open("/tmp/sub-sec.json"))
for k,v in sorted((s.get("data") or {}).items()):
  raw=base64.b64decode(v)
  # show host-like values only (safe)
  if "HOST" in k or "PORT" in k or "NAME" in k or "SSL" in k or k in ("POSTGRES_HOST","POSTGRES_PORT"):
    print(f"{k}={raw.decode('utf-8','replace')!r}")
  else:
    print(f"{k}: len={len(raw)}")
PY

echo "=== identity/notif/ui ==="
kubectl get pods -n am-apps-dr | grep -iE 'NAME|identity|notification|modern|subscription|gateway'
curl -sS "https://am-dr.asrax.in/identity/health"; echo
curl -sS -o /dev/null -w "ui %{http_code} gateway %{http_code}\n" "https://am-dr.asrax.in/" "https://am-dr.asrax.in/gateway"
