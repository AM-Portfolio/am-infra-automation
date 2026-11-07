#!/usr/bin/env bash
# Detect NotReady / exited Kind docker nodes and docker-restart them.
#
# Kind workers die when host inotify limits are too low (systemd PID1:
# "Failed to create control group inotify object: Too many open files").
# This script raises durable sysctls, then restarts any matching Kind node
# container that is exited or whose kube node is NotReady.
#
# Usage (root on VPS):
#   ENV=prod bash ensure-kind-node-ready.sh
#   bash ensure-kind-node-ready.sh prod
#   bash ensure-kind-node-ready.sh prod --dry-run
#
# Safe: never kind delete. Only docker start/restart of existing node containers.
# Recreate (docker rm + kubeadm join) is OUT OF SCOPE — break-glass only.
set -euo pipefail

ENV_NAME="${ENV:-prod}"
DRY_RUN=0
WAIT_SECS="${WAIT_SECS:-300}"
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    prod|preprod|dr|dev|obs) ENV_NAME="$arg" ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

ASRAX_HOME="${ASRAX_HOME:-${HOME:-/root}/.asrax}"
WATCHES="${AM_INOTIFY_WATCHES:-1048576}"
INSTANCES="${AM_INOTIFY_INSTANCES:-16384}"
SYSCTL_DROPIN="/etc/sysctl.d/99-kind-inotify.conf"

echo "== ensure-kind-node-ready ENV=$ENV_NAME dry_run=$DRY_RUN =="

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: run as root (sysctl + docker restart Kind nodes)" >&2
    exit 1
  fi
}

ensure_inotify() {
  local cur_w cur_i
  cur_w=$(sysctl -n fs.inotify.max_user_watches 2>/dev/null || echo 0)
  cur_i=$(sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo 0)
  echo "inotify watches=$cur_w instances=$cur_i (want >= $WATCHES / $INSTANCES)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY-RUN: would ensure $SYSCTL_DROPIN + sysctl -w"
    return 0
  fi
  cat >"$SYSCTL_DROPIN" <<EOF
# AM Kind: systemd inside Kind nodes needs high inotify (Too many open files)
fs.inotify.max_user_watches=${WATCHES}
fs.inotify.max_user_instances=${INSTANCES}
EOF
  sysctl -w "fs.inotify.max_user_watches=${WATCHES}" >/dev/null
  sysctl -w "fs.inotify.max_user_instances=${INSTANCES}" >/dev/null
  echo "inotify raised + persisted in $SYSCTL_DROPIN"
}

# Resolve infra kubeconfig for Ready checks (best-effort).
resolve_kc() {
  local cands=(
    "$ASRAX_HOME/kubeconfig.am-${ENV_NAME}-infra.yaml"
    "$ASRAX_HOME/kubeconfig.${ENV_NAME}"
    "/home/am-ops/.asrax/kubeconfig.am-${ENV_NAME}-infra.yaml"
    "/home/am-ops/.asrax/kubeconfig.${ENV_NAME}"
  )
  local f
  for f in "${cands[@]}"; do
    if [[ -f "$f" ]]; then
      echo "$f"
      return 0
    fi
  done
  return 1
}

# Returns: ready | notready | absent
node_status_via_kubectl() {
  local name="$1" kc="$2"
  local st
  if ! kubectl --kubeconfig "$kc" get node "$name" >/dev/null 2>&1; then
    echo absent
    return 0
  fi
  st=$(kubectl --kubeconfig "$kc" get node "$name" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  if [[ "$st" == "True" ]]; then
    echo ready
  else
    echo notready
  fi
}

node_ready_via_kubectl() {
  local name="$1" kc="$2"
  [[ "$(node_status_via_kubectl "$name" "$kc")" == "ready" ]]
}

# Kind docker node containers for this env (infra + apps; obs is single-node).
list_kind_node_containers() {
  docker ps -a --format '{{.Names}}' | grep -E "^am-${ENV_NAME}-(infra|apps|platform)-" || true
  if [[ "$ENV_NAME" == "obs" ]]; then
    docker ps -a --format '{{.Names}}' | grep -E '^am-obs' || true
  fi
}

container_running() {
  local name="$1"
  [[ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || echo false)" == "true" ]]
}

restart_node() {
  local name="$1"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY-RUN: would docker restart $name"
    return 0
  fi
  echo "docker restart $name"
  # Prefer restart; if exited, start is enough — restart works for both.
  if ! docker restart "$name"; then
    echo "WARN: docker restart failed for $name; trying docker start" >&2
    docker start "$name" || {
      echo "ERROR: docker start/restart failed for $name (recreate is break-glass; not done here)" >&2
      return 1
    }
  fi
}

wait_running() {
  local name="$1" i
  for i in $(seq 1 30); do
    if container_running "$name"; then
      # Give systemd a moment past PID1
      sleep 5
      if container_running "$name"; then
        echo "$name container Running"
        return 0
      fi
    fi
    sleep 2
  done
  echo "ERROR: $name still not Running after restart" >&2
  docker logs --tail 40 "$name" 2>&1 | tail -40 || true
  return 1
}

wait_ready() {
  local name="$1" kc="${2:-}" i st
  [[ -n "$kc" ]] || return 0
  for i in $(seq 1 "$((WAIT_SECS / 5))"); do
    if node_ready_via_kubectl "$name" "$kc"; then
      echo "$name Ready"
      return 0
    fi
    sleep 5
  done
  st=$(kubectl --kubeconfig "$kc" get node "$name" --no-headers 2>/dev/null || echo missing)
  echo "WARN: $name not Ready within ${WAIT_SECS}s ($st)" >&2
  return 1
}

need_root
ensure_inotify

KC=""
if KC=$(resolve_kc); then
  echo "kubeconfig=$KC"
else
  echo "WARN: no infra kubeconfig under $ASRAX_HOME — container-only checks"
  KC=""
fi

fixed=0
failed=0
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  # Skip non-node helpers if any match slipped through
  case "$name" in
    *-control-plane|*-worker|*-worker[0-9]*) ;;
    *) continue ;;
  esac

  running=0
  container_running "$name" && running=1

  # Pick kubeconfig that actually lists this node (infra vs apps).
  node_kc=""
  nst="absent"
  if [[ -n "$KC" ]]; then
    nst=$(node_status_via_kubectl "$name" "$KC")
    if [[ "$nst" != "absent" ]]; then
      node_kc="$KC"
    fi
  fi
  # Apps cluster kubeconfig (common Contabo layout)
  if [[ "$nst" == "absent" ]]; then
    for cand in \
      "$ASRAX_HOME/kubeconfig.am-${ENV_NAME}-apps.yaml" \
      "/home/am-ops/.asrax/kubeconfig.am-${ENV_NAME}-apps.yaml"; do
      if [[ -f "$cand" ]]; then
        nst=$(node_status_via_kubectl "$name" "$cand")
        if [[ "$nst" != "absent" ]]; then
          node_kc="$cand"
          break
        fi
      fi
    done
  fi

  if [[ "$nst" == "ready" && "$running" -eq 1 ]]; then
    echo "OK $name Running+Ready"
    continue
  fi

  if [[ "$nst" == "absent" ]]; then
    # Unknown to our kubeconfigs: only heal exited containers, never wait Ready.
    if [[ "$running" -eq 1 ]]; then
      echo "OK $name Running (no matching cluster kubeconfig)"
      continue
    fi
    reason="container-not-running"
    node_kc=""
  elif [[ "$running" -eq 0 ]]; then
    reason="container-not-running"
  else
    reason="kube-NotReady"
  fi

  echo "FIX $name ($reason)"
  if restart_node "$name"; then
    if wait_running "$name"; then
      if [[ -n "$node_kc" ]]; then
        wait_ready "$name" "$node_kc" || true
      fi
      fixed=$((fixed + 1))
    else
      failed=$((failed + 1))
    fi
  else
    failed=$((failed + 1))
  fi
done < <(list_kind_node_containers | sort -u)

echo "== ensure-kind-node-ready DONE fixed=$fixed failed=$failed =="
[[ "$failed" -eq 0 ]]
