#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml

echo "=== repo secrets ==="
kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=repository -o custom-columns=NAME:.metadata.name,URL:.data.url --no-headers 2>/dev/null | while read n u; do
  echo "$n $(echo $u | base64 -d 2>/dev/null || true)"
done
kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=repo-creds -o name 2>/dev/null || true

echo "=== credential files ==="
ls -la /data/am-state/credentials/ 2>&1 | head -20
ls /root/.config/gh/ 2>&1 | head -5
test -f /home/am-ops/.asrax/credentials.env && echo has_amops_creds || echo no_amops_creds
test -f /data/am-state/credentials/credentials.env && echo has_state_creds || echo no_state_creds

# Check if gh works
gh auth status 2>&1 | head -10 || true
