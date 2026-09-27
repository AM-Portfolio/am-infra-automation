#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml

# prune old replicasets / stuck pods
for d in am-identity-dr am-subscription-dr am-notification-dr am-modern-ui-dr; do
  kubectl -n am-apps-dr rollout status "deploy/$d" --timeout=120s 2>&1 | tail -5 || true
done

echo "=== pods ==="
kubectl get pods -n am-apps-dr -o wide

echo "=== identity ready ==="
kubectl get pods -n am-apps-dr -l app.kubernetes.io/instance=am-identity-dr -o jsonpath='{range .items[*]}{.metadata.name} {.status.phase} ready={.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null || \
  kubectl get pods -n am-apps-dr | grep identity

echo "=== subscription env (postgres) ==="
POD=$(kubectl get pods -n am-apps-dr -l app.kubernetes.io/name=am-subscription -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -z "${POD:-}" ]; then POD=$(kubectl get pods -n am-apps-dr --field-selector=status.phase=Running -o name | grep subscription | head -1 | cut -d/ -f2 || true); fi
# prefer newest subscription pod
POD=$(kubectl get pods -n am-apps-dr --sort-by=.metadata.creationTimestamp -o name | grep subscription | tail -1 | cut -d/ -f2)
echo "pod=$POD"
kubectl exec -n am-apps-dr "$POD" -- sh -c 'env | grep -iE "POSTGRES|DATABASE|AM_SUBSCRIPTION_DB|HOST" | sed "s/=.*/=***/"' 2>&1 || \
  kubectl get pod -n am-apps-dr "$POD" -o yaml | grep -iE 'POSTGRES|AM_SUBSCRIPTION' | head -40

echo "=== notification env (mongo) ==="
NPOD=$(kubectl get pods -n am-apps-dr --sort-by=.metadata.creationTimestamp -o name | grep notification | tail -1 | cut -d/ -f2)
echo "pod=$NPOD"
kubectl exec -n am-apps-dr "$NPOD" -- sh -c 'env | grep -iE "MONGO|PASSWORD|URI|DB_" | sed "s/=.*/=***/"' 2>&1 || true
kubectl get secret -n am-apps-dr am-notification-dr-synced-secrets -o jsonpath='{.data}' 2>/dev/null | tr ',' '\n' | cut -d: -f1 | head -40

echo "=== subscription synced secret keys ==="
kubectl get secret -n am-apps-dr am-subscription-dr-synced-secrets -o jsonpath='{.data}' 2>/dev/null | tr ',' '\n' | cut -d: -f1 | head -40

echo "=== curl identity via in-cluster ==="
kubectl run curl-id --rm -i --restart=Never --image=curlimages/curl:8.5.0 -n am-apps-dr -- \
  curl -sS -o /dev/null -w "%{http_code}\n" http://am-identity-dr:8080/health 2>&1 | tail -5

echo "=== external identity path ==="
curl -sS -o /tmp/id.body -w "%{http_code}\n" -H "Host: am-dr.asrax.in" "https://am-dr.asrax.in/identity/health" || true
head -c 120 /tmp/id.body; echo
