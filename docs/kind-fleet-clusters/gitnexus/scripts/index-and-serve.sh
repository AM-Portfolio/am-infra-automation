#!/usr/bin/env bash
set -euo pipefail
REPOS_ROOT=/opt/am/repos
HUB_ROOT=/opt/am/gitnexus
REGISTRY_ROOT=/var/lib/gitnexus
mkdir -p "$REGISTRY_ROOT"
chown -R gitnexus:gitnexus "$REGISTRY_ROOT" /opt/am

echo "[index] am-platform"
sudo -u gitnexus env \
  AM_REPOS_ROOT="$REPOS_ROOT" \
  AM_GITNEXUS_HUB="$HUB_ROOT" \
  AM_CODE_INTELLIGENCE_HOME="$HUB_ROOT" \
  GITNEXUS_HOME="$REGISTRY_ROOT" \
  GITNEXUS_LBUG_BUFFER_POOL_SIZE=2147483648 \
  bash -lc "cd '$HUB_ROOT' && (npm run index:one -- -Repo am-platform || gitnexus analyze '$REPOS_ROOT/am-platform') && (npm run group:sync || true)"

echo "[systemd]"
install -m 0644 "$HUB_ROOT/vps/gitnexus-serve.service" /etc/systemd/system/gitnexus-serve.service
cat >/etc/profile.d/gitnexus.sh <<EOF
export AM_REPOS_ROOT=$REPOS_ROOT
export AM_GITNEXUS_HUB=$HUB_ROOT
export AM_CODE_INTELLIGENCE_HOME=$HUB_ROOT
export GITNEXUS_HOME=$REGISTRY_ROOT
export GITNEXUS_LBUG_BUFFER_POOL_SIZE=2147483648
EOF
systemctl daemon-reload
systemctl enable gitnexus-serve
systemctl restart gitnexus-serve
sleep 3
systemctl --no-pager -l status gitnexus-serve || true
ss -lntp | grep 4747 || true
curl -sS -o /dev/null -w "127.0.0.1: %{http_code}\n" http://127.0.0.1:4747/ || true
curl -sS -o /dev/null -w "172.18.0.1: %{http_code}\n" http://172.18.0.1:4747/ || true
echo INDEX_SERVE_DONE
