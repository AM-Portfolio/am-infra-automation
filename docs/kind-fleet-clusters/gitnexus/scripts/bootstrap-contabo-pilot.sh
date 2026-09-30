#!/usr/bin/env bash
# Contabo nonprod: GitNexus hub + am-platform pilot + systemd serve.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

GITNEXUS_USER="${GITNEXUS_USER:-gitnexus}"
REPOS_ROOT="${REPOS_ROOT:-/opt/am/repos}"
HUB_ROOT="${HUB_ROOT:-/opt/am/gitnexus}"
REGISTRY_ROOT="${REGISTRY_ROOT:-/var/lib/gitnexus}"
GITNEXUS_VERSION="${GITNEXUS_VERSION:-1.6.9}"

echo "[1/7] user + dirs"
if ! id "$GITNEXUS_USER" &>/dev/null; then
  useradd -m -s /bin/bash "$GITNEXUS_USER"
fi
mkdir -p "$REPOS_ROOT" "$HUB_ROOT" "$REGISTRY_ROOT"
chown -R "$GITNEXUS_USER:$GITNEXUS_USER" /opt/am "$REGISTRY_ROOT"

echo "[2/7] node 20"
if ! command -v node &>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y -qq nodejs
fi
node -v
npm -v

echo "[3/7] gitnexus cli"
npm install -g "gitnexus@${GITNEXUS_VERSION}"
gitnexus --version || true

echo "[4/7] clone hub + am-platform"
if [[ ! -d "$HUB_ROOT/.git" ]]; then
  sudo -u "$GITNEXUS_USER" git clone --depth 1 https://github.com/AM-Portfolio/am-gitnexus.git "$HUB_ROOT"
else
  sudo -u "$GITNEXUS_USER" git -C "$HUB_ROOT" pull --ff-only || true
fi
if [[ ! -d "$REPOS_ROOT/am-platform/.git" ]]; then
  sudo -u "$GITNEXUS_USER" git clone --depth 1 https://github.com/AM-Portfolio/am-platform.git "$REPOS_ROOT/am-platform"
else
  sudo -u "$GITNEXUS_USER" git -C "$REPOS_ROOT/am-platform" pull --ff-only || true
fi

echo "[5/7] index am-platform"
sudo -u "$GITNEXUS_USER" env \
  AM_REPOS_ROOT="$REPOS_ROOT" \
  AM_GITNEXUS_HUB="$HUB_ROOT" \
  AM_CODE_INTELLIGENCE_HOME="$HUB_ROOT" \
  GITNEXUS_HOME="$REGISTRY_ROOT" \
  GITNEXUS_LBUG_BUFFER_POOL_SIZE=2147483648 \
  bash -lc "cd '$HUB_ROOT' && (npm run index:one -- -Repo am-platform || gitnexus analyze '$REPOS_ROOT/am-platform') && (npm run group:sync || true)"

echo "[6/7] systemd unit"
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

echo "[7/7] health"
curl -sS -o /tmp/gnx-health.out -w "127.0.0.1: %{http_code}\n" http://127.0.0.1:4747/ || true
head -c 200 /tmp/gnx-health.out; echo
curl -sS -o /dev/null -w "172.18.0.1: %{http_code}\n" http://172.18.0.1:4747/ || true
echo DONE
