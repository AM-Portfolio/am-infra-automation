#!/bin/bash
# Runs inside am-kubeapi-proxy-ensure (host Docker, --restart always).
# Rewrites kubeconfig to Kind control-plane Docker DNS, then keeps kubeapi-proxy applied.
# Also self-heals CoreDNS:
#   - one-line `health { lameduck Ns }` crashes CoreDNS
#   - missing `forward .` → SERVFAIL → cloudflared CF 1033 / ImagePullBackOff
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

_patch_coredns() {
  local new="$1" patchf
  patchf="$(mktemp)"
  if command -v python3 >/dev/null 2>&1; then
    NEW_CORE="$new" python3 - <<'PY' >"$patchf"
import json, os
print(json.dumps({"data": {"Corefile": os.environ["NEW_CORE"]}}))
PY
  elif command -v jq >/dev/null 2>&1; then
    jq -n --arg c "$new" '{data:{Corefile:$c}}' >"$patchf"
  else
    echo "$(date -u +%FT%TZ) WARN: no python3/jq — cannot patch CoreDNS" >&2
    rm -f "$patchf"
    return 1
  fi
  kubectl -n kube-system patch cm coredns --type merge --patch-file "$patchf" || true
  rm -f "$patchf"
  kubectl -n kube-system rollout restart deploy/coredns || true
  kubectl -n kube-system rollout status deploy/coredns --timeout=90s || true
  kubectl -n infra rollout restart deploy/cloudflared 2>/dev/null || true
  return 0
}

ensure_coredns_health() {
  local core new ready_dns cf_ready
  core="$(kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' 2>/dev/null || true)"
  [[ -z "$core" ]] && return 0
  new="$core"

  # One-line health { lameduck Ns } → multiline block.
  if ! { printf '%s\n' "$new" | grep -qE '^[[:space:]]*health[[:space:]]*\{[[:space:]]*$' \
    && printf '%s\n' "$new" | grep -qE '^[[:space:]]*lameduck[[:space:]]'; }; then
    if printf '%s\n' "$new" | grep -qE 'health[[:space:]]*\{[[:space:]]*lameduck'; then
      new="$(printf '%s\n' "$new" | sed -E \
        's/^([ \t]*)health[ \t]*\{[ \t]*lameduck[ \t]+([^}]+)\}[ \t]*$/\1health {\n\1   lameduck \2\n\1}/')"
    fi
  fi

  # Missing forward → insert public upstream (never leave CoreDNS without upstream).
  if ! printf '%s\n' "$new" | grep -qE '^[[:space:]]*forward[[:space:]]+\.'; then
    echo "$(date -u +%FT%TZ) CoreDNS missing forward — inserting 8.8.8.8/8.8.4.4"
    if printf '%s\n' "$new" | grep -qE '^[[:space:]]*cache[[:space:]]'; then
      new="$(printf '%s\n' "$new" | sed -E 's/^([ \t]*)cache[ \t]/    forward . 8.8.8.8 8.8.4.4 {\n       max_concurrent 1000\n    }\n\1cache /')"
    elif printf '%s\n' "$new" | grep -qE '^[[:space:]]*loop[[:space:]]*$'; then
      new="$(printf '%s\n' "$new" | sed -E 's/^([ \t]*)loop[[:space:]]*$/    forward . 8.8.8.8 8.8.4.4 {\n       max_concurrent 1000\n    }\n\1loop/')"
    else
      new="${new}
    forward . 8.8.8.8 8.8.4.4 {
       max_concurrent 1000
    }"
    fi
  fi

  if [[ "$new" != "$core" ]]; then
    echo "$(date -u +%FT%TZ) patching CoreDNS Corefile (health/forward heal)"
    _patch_coredns "$new" || true
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
