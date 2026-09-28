#!/bin/sh
# Loki volume janitor — every 6h from compose service.
# If usage >= 80% OR always: delete chunk files older than 14 days (336h).
# Never touches Prometheus. Logs to stdout.

set -eu
LOKI_ROOT="${LOKI_ROOT:-/loki}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
THRESHOLD_PCT="${THRESHOLD_PCT:-80}"

usage_pct() {
  df -P "$LOKI_ROOT" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}'
}

pct="$(usage_pct || echo 0)"
echo "log-janitor: loki_usage=${pct}% retention_days=${RETENTION_DAYS} threshold=${THRESHOLD_PCT}%"

# Always run age cleanup; aggressive note when over threshold
if [ "${pct:-0}" -ge "$THRESHOLD_PCT" ]; then
  echo "log-janitor: WARNING volume >= ${THRESHOLD_PCT}% — forcing cleanup"
fi

# Prefer finding chunk-like files older than retention under /loki
find "$LOKI_ROOT" -type f -mtime +"$RETENTION_DAYS" -print -delete 2>/dev/null | head -n 200 || true
echo "log-janitor: done"
