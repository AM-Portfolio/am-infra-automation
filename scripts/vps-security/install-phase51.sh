#!/usr/bin/env bash
# Phase 5.x bootstrap (run once as root on a VPS).
# Creates am-ops (key-only, no sudoers), am-ops-guard, break-glass-kind.sh (G1),
# /data/am-state, break-glass log, hardens root kubeconfig modes.
#
# Guard is installed at /usr/local/bin/{kubectl,kind,terraform} so BatchMode /
# non-interactive SSH (no profile.d) still hits the guard for am-ops. Real
# binaries live under /usr/local/libexec/am-real/.
set -euo pipefail

[[ "$(id -u)" -eq 0 ]] || { echo "run as root" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD_DIR="/opt/am-ops-guard/bin"
REAL_DIR="/usr/local/libexec/am-real"
BREAK_GLASS="/usr/local/sbin/break-glass-kind.sh"
LOG="/var/log/am-break-glass.log"
STATE_DIR="/data/am-state"
OPS_USER="am-ops"

echo "==> Phase 5 security install on $(hostname) as $(whoami)"

# --- am-ops user (no sudo, key-only) ---
if ! id "$OPS_USER" &>/dev/null; then
  useradd --create-home --shell /bin/bash --user-group "$OPS_USER"
  echo "created user $OPS_USER"
else
  echo "user $OPS_USER already exists"
fi

for g in sudo wheel admin; do
  if getent group "$g" &>/dev/null; then
    gpasswd -d "$OPS_USER" "$g" 2>/dev/null || true
  fi
done
rm -f /etc/sudoers.d/*am-ops* 2>/dev/null || true

passwd -l "$OPS_USER" >/dev/null 2>&1 || true
if command -v chage &>/dev/null; then
  chage -E -1 -I -1 -m 0 "$OPS_USER" 2>/dev/null || true
fi

install -d -m 700 -o "$OPS_USER" -g "$OPS_USER" "/home/$OPS_USER/.ssh"
if [[ -f /root/.ssh/authorized_keys ]]; then
  install -m 600 -o "$OPS_USER" -g "$OPS_USER" /root/.ssh/authorized_keys "/home/$OPS_USER/.ssh/authorized_keys"
  echo "copied root authorized_keys -> $OPS_USER"
else
  echo "WARN: /root/.ssh/authorized_keys missing — ensure am-ops has a key before disabling passwords" >&2
fi

SSHD_DROPIN="/etc/ssh/sshd_config.d/99-am-ops-phase51.conf"
mkdir -p /etc/ssh/sshd_config.d
cat >"$SSHD_DROPIN" <<'EOF'
# Phase 5 — day-2 prefers keys; passwords locked for am-ops via passwd -l
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
EOF
if command -v systemctl &>/dev/null && systemctl is-active --quiet sshd 2>/dev/null; then
  systemctl reload sshd || systemctl reload ssh || true
elif command -v systemctl &>/dev/null && systemctl is-active --quiet ssh 2>/dev/null; then
  systemctl reload ssh || true
fi
echo "sshd drop-in: $SSHD_DROPIN (PasswordAuthentication no)"

# --- relocate real binaries, install wrappers at /usr/local/bin ---
mkdir -p "$REAL_DIR" "$GUARD_DIR"

relocate_real() {
  local bin="$1"
  local dest="$REAL_DIR/$bin"
  # Already relocated
  if [[ -x "$dest" ]]; then
    return 0
  fi
  # Current /usr/local/bin may already be our wrapper — do not move wrappers
  if [[ -x "/usr/local/bin/$bin" ]] && ! grep -q 'am-ops-guard' "/usr/local/bin/$bin" 2>/dev/null; then
    mv "/usr/local/bin/$bin" "$dest"
    echo "relocated /usr/local/bin/$bin -> $dest"
    return 0
  fi
  for cand in "/usr/bin/$bin" "/bin/$bin"; do
    if [[ -x "$cand" ]]; then
      cp -a "$cand" "$dest"
      echo "copied $cand -> $dest"
      return 0
    fi
  done
  echo "note: no real $bin found yet (wrapper will 127 until installed)"
}

for bin in kubectl kind terraform; do
  relocate_real "$bin"
  install -m 755 "$SCRIPT_DIR/am-ops-guard-$bin" "/usr/local/bin/$bin"
  install -m 755 "$SCRIPT_DIR/am-ops-guard-$bin" "$GUARD_DIR/$bin"
done

# Env for real paths (also used by profile.d PATH prepend)
cat > /etc/profile.d/am-ops-guard.sh <<EOF
# Phase 5 — am-ops: prefer guard dir; all users hit /usr/local/bin wrappers
export AM_OPS_REAL_KUBECTL=$REAL_DIR/kubectl
export AM_OPS_REAL_KIND=$REAL_DIR/kind
export AM_OPS_REAL_TERRAFORM=$REAL_DIR/terraform
if [ "\$(id -un 2>/dev/null)" = "am-ops" ]; then
  export PATH="$GUARD_DIR:/usr/local/bin:\$PATH"
fi
EOF
chmod 644 /etc/profile.d/am-ops-guard.sh

# Non-interactive BatchMode: bash still skips .bashrc unless these exist + ssh forces
# Also set BASH_ENV for non-interactive bash started as am-ops
BASHRC_SNIP='# Phase 5 am-ops-guard
if [ -f /etc/profile.d/am-ops-guard.sh ]; then
  . /etc/profile.d/am-ops-guard.sh
fi
'
for f in "/home/$OPS_USER/.bashrc" "/home/$OPS_USER/.profile" "/home/$OPS_USER/.bash_profile"; do
  touch "$f"
  chown "$OPS_USER:$OPS_USER" "$f"
  if ! grep -q 'am-ops-guard' "$f" 2>/dev/null; then
    printf '\n%s\n' "$BASHRC_SNIP" >>"$f"
  fi
done
# Ensure .bashrc runs even when non-interactive (ssh command) via BASH_ENV
if ! grep -q 'BASH_ENV' "/home/$OPS_USER/.bash_profile" 2>/dev/null; then
  printf '\nexport BASH_ENV=$HOME/.bashrc\n' >>"/home/$OPS_USER/.bash_profile"
fi
# sshd environment for am-ops (optional pam) — write user env file
install -d -m 755 /etc/environment.d 2>/dev/null || true
# PAM user_env: ~/.pam_environment is deprecated; use ~/.ssh/environment if PermitUserEnvironment
# Rely primarily on /usr/local/bin wrappers (works without shell rc).

# --- G1 break-glass ---
install -m 750 -o root -g root "$SCRIPT_DIR/break-glass-kind.sh" "$BREAK_GLASS"
touch "$LOG"
chmod 640 "$LOG"
chown root:root "$LOG"
if getent group adm &>/dev/null; then
  chgrp adm "$LOG" || true
  usermod -aG adm "$OPS_USER" 2>/dev/null || true
fi

# --- /data/am-state ---
mkdir -p "$STATE_DIR"
chown "$OPS_USER:$OPS_USER" "$STATE_DIR"
chmod 775 "$STATE_DIR"
mkdir -p /data
chmod 755 /data

# --- root kubeconfig 0400 ---
shopt -s nullglob
for kc in /root/.kube/config /root/.kube/*.yaml; do
  [[ -e "$kc" ]] || continue
  chown root:root "$kc"
  chmod 0400 "$kc"
  echo "hardened $kc -> 0400"
done
shopt -u nullglob

if [[ -d /root/.kube ]]; then
  chmod 700 /root/.kube || true
fi

echo "==> Phase 5 security install complete"
echo "    user=$OPS_USER (no sudoers)"
echo "    wrappers=/usr/local/bin/{kubectl,kind,terraform} -> $REAL_DIR"
echo "    g1=$BREAK_GLASS"
echo "    log=$LOG"
echo "    state=$STATE_DIR"
