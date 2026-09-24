#!/usr/bin/env bash
# WireGuard VPS1↔VPS3 for Phase 5.3 (G20 path).
# Usage (as root on each host):
#   ROLE=vps1 PEER_PUBLIC_IP=129.121.128.131 bash install-wireguard-vps1-vps3.sh
#   ROLE=vps3 PEER_PUBLIC_IP=203.174.22.129 bash install-wireguard-vps1-vps3.sh
#
# Optional: PEER_PUBKEY=... (if peer already generated; otherwise script prints
# this host's pubkey and exits 2 so the orchestrator can re-run with exchange).
#
# Addressing: VPS1=10.77.1.1/24  VPS3=10.77.1.2/24  UDP 51820
# Firewall: DROP :5432/:27017 on public NIC; ACCEPT those on wg0 from peer only.
set -euo pipefail

[[ "$(id -u)" -eq 0 ]] || { echo "run as root" >&2; exit 1; }

ROLE="${ROLE:-}"
PEER_PUBLIC_IP="${PEER_PUBLIC_IP:-}"
PEER_PUBKEY="${PEER_PUBKEY:-}"
WG_PORT="${WG_PORT:-51820}"
WG_IF="${WG_IF:-wg0}"
CONF_DIR="/etc/wireguard"
KEY_DIR="$CONF_DIR/am-keys"

case "$ROLE" in
  vps1)
    SELF_WG_IP="10.77.1.1/24"
    PEER_WG_IP="10.77.1.2/32"
    ;;
  vps3)
    SELF_WG_IP="10.77.1.2/24"
    PEER_WG_IP="10.77.1.1/32"
    ;;
  *)
    echo "ROLE must be vps1 or vps3" >&2
    exit 2
    ;;
esac

[[ -n "$PEER_PUBLIC_IP" ]] || { echo "PEER_PUBLIC_IP required" >&2; exit 2; }

echo "==> WireGuard $ROLE on $(hostname) peer=$PEER_PUBLIC_IP"

export DEBIAN_FRONTEND=noninteractive
if command -v apt-get >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq wireguard wireguard-tools iptables iptables-persistent 2>/dev/null \
    || apt-get install -y -qq wireguard wireguard-tools iptables
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y wireguard-tools iptables
fi

mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"
if [[ ! -f "$KEY_DIR/privatekey" ]]; then
  umask 077
  wg genkey | tee "$KEY_DIR/privatekey" | wg pubkey >"$KEY_DIR/publickey"
  echo "generated WG keypair"
fi
PRIV="$(cat "$KEY_DIR/privatekey")"
PUB="$(cat "$KEY_DIR/publickey")"
echo "LOCAL_PUBKEY=$PUB"

if [[ -z "$PEER_PUBKEY" ]]; then
  echo "PEER_PUBKEY not set — print local pubkey and exit for exchange"
  exit 3
fi

# Enable forwarding (replica traffic)
sysctl -w net.ipv4.ip_forward=1 >/dev/null
mkdir -p /etc/sysctl.d
echo 'net.ipv4.ip_forward=1' >/etc/sysctl.d/99-am-wg-forward.conf

cat >"$CONF_DIR/$WG_IF.conf" <<EOF
[Interface]
Address = $SELF_WG_IP
ListenPort = $WG_PORT
PrivateKey = $PRIV
# PostUp/PostDown firewall for store ports
PostUp = /usr/local/sbin/am-wg-firewall.sh up
PostDown = /usr/local/sbin/am-wg-firewall.sh down

[Peer]
PublicKey = $PEER_PUBKEY
Endpoint = $PEER_PUBLIC_IP:$WG_PORT
AllowedIPs = $PEER_WG_IP
PersistentKeepalive = 25
EOF
chmod 600 "$CONF_DIR/$WG_IF.conf"

# Detect public NIC (default route)
PUBLIC_IF="$(ip -4 route show default | awk '{print $5; exit}')"
PUBLIC_IF="${PUBLIC_IF:-eth0}"
PEER_WG_HOST="${PEER_WG_IP%/*}"

cat >/usr/local/sbin/am-wg-firewall.sh <<EOF
#!/usr/bin/env bash
# Allow PG/Mongo only on WireGuard; block on public NIC.
set -euo pipefail
ACTION="\${1:-up}"
PUB_IF="$PUBLIC_IF"
WG_IF="$WG_IF"
PEER="$PEER_WG_HOST"
CHAIN="AM-WG-STORES"

ensure_chain() {
  iptables -N "\$CHAIN" 2>/dev/null || iptables -F "\$CHAIN"
  # jump once from INPUT
  iptables -C INPUT -j "\$CHAIN" 2>/dev/null || iptables -I INPUT 1 -j "\$CHAIN"
}

if [[ "\$ACTION" == "down" ]]; then
  iptables -D INPUT -j "\$CHAIN" 2>/dev/null || true
  iptables -F "\$CHAIN" 2>/dev/null || true
  iptables -X "\$CHAIN" 2>/dev/null || true
  exit 0
fi

ensure_chain
iptables -F "\$CHAIN"
# Block store ports on public NIC (and any non-WG)
iptables -A "\$CHAIN" -i "\$PUB_IF" -p tcp --dport 5432 -j DROP
iptables -A "\$CHAIN" -i "\$PUB_IF" -p tcp --dport 27017 -j DROP
# Also block if bound publicly but packet arrives on any non-wg iface
iptables -A "\$CHAIN" -i "\$WG_IF" -p tcp -s "\$PEER" --dport 5432 -j ACCEPT
iptables -A "\$CHAIN" -i "\$WG_IF" -p tcp -s "\$PEER" --dport 27017 -j ACCEPT
iptables -A "\$CHAIN" -p tcp --dport 5432 ! -i "\$WG_IF" -j DROP
iptables -A "\$CHAIN" -p tcp --dport 27017 ! -i "\$WG_IF" -j DROP
# Allow WG UDP
iptables -A "\$CHAIN" -p udp --dport $WG_PORT -j ACCEPT
EOF
chmod 755 /usr/local/sbin/am-wg-firewall.sh

systemctl enable "wg-quick@$WG_IF" >/dev/null 2>&1 || true
systemctl restart "wg-quick@$WG_IF"

# Apply firewall now as well (PostUp also runs)
/usr/local/sbin/am-wg-firewall.sh up

echo "==> WG up: $(ip -4 -br addr show "$WG_IF" 2>/dev/null || true)"
wg show
echo "SELF_WG=${SELF_WG_IP%/*} PEER_WG=$PEER_WG_HOST PUBLIC_IF=$PUBLIC_IF"
