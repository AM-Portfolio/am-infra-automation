#!/usr/bin/env bash
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
echo "=== ingress ==="
kubectl get ingress -n am-apps-dr -o wide 2>&1
echo "=== pods identity wave ==="
kubectl get pods -n am-apps-dr 2>&1 | grep -iE 'NAME|identity|subscription|notification|gateway|modern|proxy' || kubectl get pods -n am-apps-dr
echo "=== modern-ui ingress describe ==="
kubectl get ingress -n am-apps-dr am-modern-ui-dr -o yaml 2>&1 | head -60
