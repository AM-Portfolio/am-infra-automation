#!/usr/bin/env bash
# Install Kind VPS reboot resilience units (root). Usage: ENV=prod bash install-kind-fleet-systemd.sh
set -euo pipefail
ENV_NAME="${1:-${ENV:-prod}}"
REPO="${REPO:-/root/am-repos/am-infra-automation}"
UNIT_DIR=/etc/systemd/system
ASRAX_HOME="${ASRAX_HOME:-/home/am-ops/.asrax}"
SRC="$REPO/terraform/kind-fleet/scripts"

mkdir -p "$REPO/terraform/kind-fleet/scripts/systemd"
cp "$SRC/systemd/am-refresh-bridges.service" "$UNIT_DIR/"
cp "$SRC/systemd/am-refresh-bridges.timer" "$UNIT_DIR/"
cp "$SRC/systemd/am-refresh-exposer-hostaliases.service" "$UNIT_DIR/"
cp "$SRC/systemd/am-refresh-exposer-hostaliases.timer" "$UNIT_DIR/"
cp "$SRC/systemd/am-kind-fleet-boot.service" "$UNIT_DIR/"
cp "$SRC/systemd/am-kind-fleet-boot.timer" "$UNIT_DIR/"

for u in am-refresh-bridges.service am-refresh-exposer-hostaliases.service am-kind-fleet-boot.service; do
  sed -i "s|/opt/am/am-infra-automation|$REPO|g" "$UNIT_DIR/$u"
  sed -i "s|/root/am-repos/am-infra-automation|$REPO|g" "$UNIT_DIR/$u"
  # rewrite ENV= line
  if grep -q '^Environment=ENV=' "$UNIT_DIR/$u"; then
    sed -i "s|^Environment=ENV=.*|Environment=ENV=$ENV_NAME|" "$UNIT_DIR/$u"
  else
    sed -i "/^\[Service\]/a Environment=ENV=$ENV_NAME" "$UNIT_DIR/$u"
  fi
  if grep -q '^Environment=ASRAX_HOME=' "$UNIT_DIR/$u"; then
    sed -i "s|^Environment=ASRAX_HOME=.*|Environment=ASRAX_HOME=$ASRAX_HOME|" "$UNIT_DIR/$u"
  fi
done

chmod +x \
  "$SRC/refresh-cross-cluster-bridges.sh" \
  "$SRC/refresh-exposer-hostaliases.sh" \
  "$SRC/ensure-port-exposer.sh" \
  "$SRC/kind-fleet-boot.sh" \
  2>/dev/null || true

systemctl daemon-reload
systemctl enable --now am-refresh-bridges.timer
systemctl enable --now am-refresh-exposer-hostaliases.timer
systemctl enable --now am-kind-fleet-boot.timer
echo "installed ENV=$ENV_NAME"
systemctl list-timers --all | grep -E 'am-refresh|am-kind-fleet' || true
