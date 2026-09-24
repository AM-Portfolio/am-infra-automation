#!/usr/bin/env bash
# G1 break-glass allowlist (root only).
# Allowed:
#   kind create|delete …
#   docker stop|start <Kind node container>
#   systemctl stop|start cloudflared
#   pg_ctl promote …
#   mongosh|mongo … rs.stepUp …
# Log: /var/log/am-break-glass.log
set -euo pipefail

LOG="${AM_BREAK_GLASS_LOG:-/var/log/am-break-glass.log}"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
WHO="$(whoami 2>/dev/null || echo unknown)"
TTY="$(tty 2>/dev/null || echo notty)"

log() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  echo "[$TS] user=$WHO tty=$TTY $*" | tee -a "$LOG" >&2
}

die() {
  log "REFUSED: $*"
  echo "break-glass-kind: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage (root only): break-glass-kind.sh -- <allowlisted command>

Allowlist:
  kind create|delete …
  docker stop|start <container>   # Kind nodes only (label io.x-k8s.kind.cluster)
  systemctl stop|start cloudflared
  pg_ctl promote …
  mongosh|mongo …                 # must include rs.stepUp

Examples:
  break-glass-kind.sh -- kind create cluster --name am-prod-infra
  break-glass-kind.sh -- docker stop am-prod-infra-control-plane
  break-glass-kind.sh -- systemctl start cloudflared
  break-glass-kind.sh -- pg_ctl promote -D /var/lib/postgresql/data
  break-glass-kind.sh -- mongosh --eval 'rs.stepUp()'
EOF
}

[[ "$(id -u)" -eq 0 ]] || die "must run as root (no sudo from am-ops)"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# Accept optional "--" then the command
if [[ "${1:-}" == "--" ]]; then
  shift
fi

[[ $# -ge 1 ]] || { usage; exit 2; }

cmd=("$1")
shift
args=("$@")

is_kind_container() {
  local name="$1"
  docker inspect -f '{{ index .Config.Labels "io.x-k8s.kind.cluster" }}' "$name" 2>/dev/null | grep -q .
}

case "${cmd[0]}" in
  kind)
    sub="${args[0]:-}"
    [[ "$sub" == "create" || "$sub" == "delete" ]] || die "kind: only create|delete allowlisted (got: ${sub:-none})"
    log "ALLOW kind $sub ${args[*]:1}"
    exec kind "$sub" "${args[@]:1}"
    ;;
  docker)
    sub="${args[0]:-}"
    [[ "$sub" == "stop" || "$sub" == "start" ]] || die "docker: only stop|start allowlisted"
    [[ ${#args[@]} -ge 2 ]] || die "docker $sub: need container name"
    # All remaining args are container names/ids
    for c in "${args[@]:1}"; do
      is_kind_container "$c" || die "docker $sub: '$c' is not a Kind node (missing io.x-k8s.kind.cluster)"
    done
    log "ALLOW docker $sub ${args[*]:1}"
    exec docker "$sub" "${args[@]:1}"
    ;;
  systemctl)
    sub="${args[0]:-}"
    unit="${args[1]:-}"
    [[ "$sub" == "stop" || "$sub" == "start" ]] || die "systemctl: only stop|start allowlisted"
    [[ "$unit" == "cloudflared" || "$unit" == "cloudflared.service" ]] || die "systemctl: only cloudflared allowlisted"
    log "ALLOW systemctl $sub $unit"
    exec systemctl "$sub" "$unit"
    ;;
  pg_ctl)
    sub="${args[0]:-}"
    [[ "$sub" == "promote" ]] || die "pg_ctl: only promote allowlisted"
    log "ALLOW pg_ctl promote ${args[*]:1}"
    exec pg_ctl promote "${args[@]:1}"
    ;;
  mongosh|mongo)
    joined="${args[*]}"
    echo "$joined" | grep -q 'rs\.stepUp' || die "${cmd[0]}: command must include rs.stepUp"
    log "ALLOW ${cmd[0]} (rs.stepUp) ${args[*]}"
    exec "${cmd[0]}" "${args[@]}"
    ;;
  *)
    die "command not on allowlist: ${cmd[0]}"
    ;;
esac
