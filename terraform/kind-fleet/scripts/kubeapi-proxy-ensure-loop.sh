#!/bin/bash
# Runs inside am-kubeapi-proxy-ensure (host Docker, --restart always).
# Rewrites kubeconfig to Kind control-plane Docker DNS, then keeps kubeapi-proxy applied.
# Also self-heals CoreDNS: one-line `health { lameduck Ns }` crashes CoreDNS → DNS down →
# cloudflared/kubeapi-proxy CrashLoop → Cloudflare 530 on kubeapi-dev / am-dev.
set -euo pipefail

INTERVAL="${INTERVAL:-30}"
APPS_CP="${APPS_CP:?APPS_CP required}"
MANIFEST="${MANIFEST:-/manifests/kubeapi-proxy.yaml}"
export KUBECONFIG=/tmp/kubeconfig

rewrite_kc() {
  # Mount should be kubeconfig.dev.local (client-cert). Rewrite server to Kind Docker DNS.
  local src=/kubeconfig.host
  sed -E "s#(server:[[:space:]]*)https?://[^[:space:]]+#\1https://${APPS_CP}:6443#" \
    "$src" > /tmp/kubeconfig
  echo "kubeconfig -> https://${APPS_CP}:6443"
}

# CoreDNS rejects `health { lameduck 5s }` on one line — must be a braced block.
ensure_coredns_health() {
  local core new patchf ready_dns cf_ready
  core="$(kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' 2>/dev/null || true)"
  [[ -z "$core" ]] && return 0

  # Already multiline health + lameduck → nothing to do (unless DNS still down below).
  if printf '%s\n' "$core" | grep -qE '^[[:space:]]*health[[:space:]]*\{[[:space:]]*$' \
    && printf '%s\n' "$core" | grep -qE '^[[:space:]]*lameduck[[:space:]]'; then
    :
  elif printf '%s\n' "$core" | grep -qE 'health[[:space:]]*\{[[:space:]]*lameduck'; then
    new="$(printf '%s\n' "$core" | sed -E \
      's/^([ \t]*)health[ \t]*\{[ \t]*lameduck[ \t]+([^}]+)\}[ \t]*$/\1health {\n\1   lameduck \2\n\1}/')"
    if [[ "$new" != "$core" ]]; then
      patchf="$(mktemp)"
      if command -v python3 >/dev/null 2>&1; then
        NEW_CORE="$new" python3 - <<'PY' >"$patchf"
import json, os
print(json.dumps({"data": {"Corefile": os.environ["NEW_CORE"]}}))
PY
      elif command -v jq >/dev/null 2>&1; then
        jq -n --arg c "$new" '{data:{Corefile:$c}}' >"$patchf"
      else
        echo "$(date -u +%FT%TZ) WARN: no python3/jq — cannot patch CoreDNS health" >&2
        rm -f "$patchf"
        return 0
      fi
      echo "$(date -u +%FT%TZ) fixing CoreDNS one-line health{lameduck}"
      kubectl -n kube-system patch cm coredns --type merge --patch-file "$patchf" || true
      rm -f "$patchf"
      kubectl -n kube-system rollout restart deploy/coredns || true
      kubectl -n kube-system rollout status deploy/coredns --timeout=90s || true
      # Tunnel pods need cluster DNS to resolve argotunnel.com
      kubectl -n infra rollout restart deploy/cloudflared 2>/dev/null || true
    fi
  fi

  ready_dns="$(kubectl -n kube-system get deploy coredns -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
  cf_ready="$(kubectl -n infra get deploy cloudflared -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
  if [[ "${ready_dns:-0}" == "0" ]]; then
    echo "$(date -u +%FT%TZ) CoreDNS ready=0 — restart"
    kubectl -n kube-system rollout restart deploy/coredns || true
  elif [[ "${cf_ready:-0}" == "0" ]]; then
    echo "$(date -u +%FT%TZ) cloudflared ready=0 (DNS up) — restart"
    kubectl -n infra rollout restart deploy/cloudflared 2>/dev/null || true
  fi
}

rewrite_kc
echo "am-kubeapi-proxy-ensure loop interval=${INTERVAL}s apps_cp=${APPS_CP}"

while true; do
  if ! kubectl get --raw=/readyz >/dev/null 2>&1; then
    echo "$(date -u +%FT%TZ) api not ready; rewrite + wait"
    rewrite_kc
    sleep 10
    continue
  fi
  ensure_coredns_health || true
  ready="$(kubectl -n infra get deploy kubeapi-proxy -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
  if [[ "${ready:-0}" != "1" ]]; then
    echo "$(date -u +%FT%TZ) applying kubeapi-proxy (ready=${ready:-0})"
    kubectl apply -f "$MANIFEST" || true
    kubectl -n infra rollout status deploy/kubeapi-proxy --timeout=60s || true
  else
    echo "$(date -u +%FT%TZ) kubeapi-proxy ready=1"
  fi
  sleep "$INTERVAL"
done
