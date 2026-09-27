#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml

# delete stuck old RS pods
kubectl delete pod -n am-apps-dr -l app.kubernetes.io/name=am-subscription --force --grace-period=0 2>/dev/null || true
sleep 8
POD=$(kubectl get pods -n am-apps-dr --sort-by=.metadata.creationTimestamp -o name | grep subscription | tail -1 | cut -d/ -f2)
echo "pod=$POD status=$(kubectl get pod -n am-apps-dr $POD -o jsonpath='{.status.phase}/{.status.containerStatuses[0].ready}')"

echo "=== all env related to db ==="
kubectl get pod -n am-apps-dr "$POD" -o json | python3 - <<'PY'
import json,sys
p=json.load(sys.stdin)
for c in p["spec"]["containers"]:
  print("container", c["name"])
  for e in c.get("env") or []:
    n=e.get("name","")
    if any(x in n.upper() for x in ("POSTGRES","DATABASE","DB_","SQL","LAGO","SSL")):
      if "value" in e:
        print(f"  {n}={e['value']!r}")
      elif "valueFrom" in e:
        print(f"  {n}=valueFrom:{json.dumps(e['valueFrom'])}")
PY

echo "=== recent logs ==="
kubectl logs -n am-apps-dr "$POD" --tail=50 2>&1 | tail -50

echo "=== secret values presence (not contents) ==="
kubectl get secret -n am-apps-dr am-subscription-dr-synced-secrets -o json | python3 - <<'PY'
import json,sys,base64
s=json.load(sys.stdin)
for k,v in sorted((s.get("data") or {}).items()):
  raw=base64.b64decode(v)
  print(f"{k}: len={len(raw)} empty={len(raw)==0}")
PY

echo "=== argo health ==="
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml
kubectl -n argocd get applications am-identity-dr am-subscription-dr am-notification-dr am-modern-ui-dr \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status --no-headers

echo "=== smoke identity+ui ==="
curl -sS -o /dev/null -w "ui %{http_code}\n" "https://am-dr.asrax.in/"
curl -sS -w "\nid-health %{http_code}\n" "https://am-dr.asrax.in/identity/health"
curl -sS -o /dev/null -w "gateway %{http_code}\n" "https://am-dr.asrax.in/gateway"
