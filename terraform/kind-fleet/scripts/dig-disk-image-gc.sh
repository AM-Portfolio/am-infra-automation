#!/usr/bin/env bash
# Dig VPS host-level Docker/Kind unused-image GC.
# Runs via systemd on the VPS OS (NOT a container / NOT in-cluster).
#
# When the filesystem that holds DockerRootDir is >= THRESHOLD_PCT used,
# prune unused images on the host and inside Kind node containerd.
# Never prunes volumes / PVCs / /data.
#
# Env:
#   THRESHOLD_PCT   default 80
#   DRY_RUN         1 = log only, no prune
#   KIND_CLUSTER    default am-dev-apps (node container name prefix)
#   LOG_FILE        default /var/log/am-dig-disk-image-gc.log
set -euo pipefail

THRESHOLD_PCT="${THRESHOLD_PCT:-80}"
DRY_RUN="${DRY_RUN:-0}"
KIND_CLUSTER="${KIND_CLUSTER:-am-dev-apps}"
LOG_FILE="${LOG_FILE:-/var/log/am-dig-disk-image-gc.log}"

ts() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }
log() {
  local line="[$(ts)] $*"
  echo "$line"
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  echo "$line" >>"$LOG_FILE" 2>/dev/null || true
}

df_used_pct() {
  local path="$1"
  # Portable: Capacity column from df -P (e.g. 14%)
  df -P "$path" 2>/dev/null | awk 'NR==2 { gsub(/%/,"",$5); print $5; exit }'
}

df_summary() {
  local path="$1"
  df -Ph "$path" 2>/dev/null | awk 'NR==2 { printf "fs=%s size=%s used=%s avail=%s use=%s mount=%s", $1,$2,$3,$4,$5,$6 }'
}

resolve_docker_root() {
  local root=""
  if command -v docker >/dev/null 2>&1; then
    root="$(docker info -f '{{.DockerRootDir}}' 2>/dev/null || true)"
  fi
  if [[ -z "$root" || ! -d "$root" ]]; then
    if [[ -d /var/lib/docker ]]; then
      root=/var/lib/docker
    else
      root=/
    fi
  fi
  printf '%s' "$root"
}

log "START dig-disk-image-gc THRESHOLD_PCT=${THRESHOLD_PCT} DRY_RUN=${DRY_RUN} KIND_CLUSTER=${KIND_CLUSTER}"

ROOT="$(resolve_docker_root)"
USED_PCT="$(df_used_pct "$ROOT" || echo "")"
if [[ -z "$USED_PCT" || ! "$USED_PCT" =~ ^[0-9]+$ ]]; then
  log "ERROR: could not read df used% for ROOT=${ROOT}"
  exit 1
fi

log "BEFORE $(df_summary "$ROOT") ROOT=${ROOT}"

if (( USED_PCT < THRESHOLD_PCT )); then
  log "SKIP used=${USED_PCT}% < threshold=${THRESHOLD_PCT}%"
  exit 0
fi

log "TRIGGER used=${USED_PCT}% >= threshold=${THRESHOLD_PCT}%"

if [[ "$DRY_RUN" == "1" ]]; then
  log "DRY_RUN=1 — would run: docker image prune -af"
  if command -v docker >/dev/null 2>&1; then
    docker system df 2>/dev/null | while IFS= read -r line; do log "docker-df: $line"; done || true
    mapfile -t NODES < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "^${KIND_CLUSTER}-" || true)
    for n in "${NODES[@]:-}"; do
      [[ -z "$n" ]] && continue
      log "DRY_RUN would: docker exec $n crictl rmi --prune"
    done
  fi
  log "AFTER (unchanged) $(df_summary "$ROOT")"
  log "END dig-disk-image-gc DRY_RUN"
  exit 0
fi

# Host unused images only (no --volumes)
if command -v docker >/dev/null 2>&1; then
  log "HOST prune: docker image prune -af"
  docker image prune -af 2>&1 | while IFS= read -r line; do log "host-prune: $line"; done || log "WARN: host image prune failed (continue)"
else
  log "WARN: docker not on PATH; skip host prune"
fi

# Kind node containerd unused images
if command -v docker >/dev/null 2>&1; then
  mapfile -t NODES < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "^${KIND_CLUSTER}-" || true)
  if [[ ${#NODES[@]} -eq 0 ]]; then
    log "WARN: no running Kind node containers matching ^${KIND_CLUSTER}-"
  fi
  for n in "${NODES[@]:-}"; do
    [[ -z "$n" ]] && continue
    log "KIND prune: docker exec $n crictl rmi --prune"
    if docker exec "$n" crictl rmi --prune 2>&1 | while IFS= read -r line; do log "kind-prune[$n]: $line"; done; then
      :
    else
      log "WARN: crictl rmi --prune failed on $n (continue)"
    fi
  done
fi

USED_AFTER="$(df_used_pct "$ROOT" || echo "?")"
log "AFTER $(df_summary "$ROOT") used_pct=${USED_AFTER}"
log "END dig-disk-image-gc"
