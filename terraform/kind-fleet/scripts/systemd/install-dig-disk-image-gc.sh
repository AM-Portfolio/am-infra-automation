#!/usr/bin/env bash
# Install dig VPS host-level disk image GC (root on am-vps-dev).
# Usage:
#   bash install-dig-disk-image-gc.sh              # live (DRY_RUN=0)
#   DRY_RUN=1 bash install-dig-disk-image-gc.sh    # first verify
#   REPO=/path bash install-dig-disk-image-gc.sh
set -euo pipefail

REPO="${REPO:-/root/am-repos/am-infra-automation}"
UNIT_DIR=/etc/systemd/system
SRC="$REPO/terraform/kind-fleet/scripts"
DRY_RUN="${DRY_RUN:-0}"
THRESHOLD_PCT="${THRESHOLD_PCT:-80}"
KIND_CLUSTER="${KIND_CLUSTER:-am-dev-apps}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: run as root on dig VPS (am-vps-dev)" >&2
  exit 1
fi

if [[ ! -f "$SRC/dig-disk-image-gc.sh" ]]; then
  echo "ERROR: missing $SRC/dig-disk-image-gc.sh (set REPO=...)" >&2
  exit 1
fi

chmod +x "$SRC/dig-disk-image-gc.sh" "$SRC/systemd/install-dig-disk-image-gc.sh"

cp "$SRC/systemd/am-dig-disk-image-gc.service" "$UNIT_DIR/"
cp "$SRC/systemd/am-dig-disk-image-gc.timer" "$UNIT_DIR/"

# Rewrite checkout path if REPO differs from unit default
sed -i "s|/root/am-repos/am-infra-automation|$REPO|g" "$UNIT_DIR/am-dig-disk-image-gc.service"
sed -i "s|/opt/am/am-infra-automation|$REPO|g" "$UNIT_DIR/am-dig-disk-image-gc.service"

# Env knobs
sed -i "s|^Environment=THRESHOLD_PCT=.*|Environment=THRESHOLD_PCT=$THRESHOLD_PCT|" "$UNIT_DIR/am-dig-disk-image-gc.service"
sed -i "s|^Environment=DRY_RUN=.*|Environment=DRY_RUN=$DRY_RUN|" "$UNIT_DIR/am-dig-disk-image-gc.service"
sed -i "s|^Environment=KIND_CLUSTER=.*|Environment=KIND_CLUSTER=$KIND_CLUSTER|" "$UNIT_DIR/am-dig-disk-image-gc.service"

systemctl daemon-reload
systemctl enable --now am-dig-disk-image-gc.timer

echo "installed dig disk image GC REPO=$REPO THRESHOLD_PCT=$THRESHOLD_PCT DRY_RUN=$DRY_RUN KIND_CLUSTER=$KIND_CLUSTER"
systemctl list-timers --all | grep -E 'am-dig-disk-image-gc' || true

echo "== one-shot now =="
systemctl start am-dig-disk-image-gc.service
systemctl status am-dig-disk-image-gc.service --no-pager || true
echo "== recent log =="
tail -n 40 /var/log/am-dig-disk-image-gc.log 2>/dev/null || true
