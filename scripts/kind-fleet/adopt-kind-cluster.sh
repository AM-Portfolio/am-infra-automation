#!/usr/bin/env bash
# Adopt an existing Kind cluster into terraform state — NEVER kind delete.
#
# Usage (from kind-fleet/<env>/<role> after terraform init):
#   adopt-kind-cluster.sh <cluster-name> [terraform-address]
#
# Examples:
#   cd /opt/.../terraform/kind-fleet/dr/apps && adopt-kind-cluster.sh am-dr-apps
#   adopt-kind-cluster.sh am-dr-platform module.cluster.kind_cluster.this
#
# If Kind already exists and TF has no kind_cluster: import + refresh kubeconfig.
# If Kind missing: leave TF to create (no delete path).
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
export AM_OPS_REAL_KIND=/usr/local/libexec/am-real/kind

CLUSTER_NAME="${1:?usage: adopt-kind-cluster.sh <am-ENV-ROLE> [tf-addr]}"
TF_ADDR="${2:-module.cluster.kind_cluster.this}"
VPS_IP="${VPS_IP:-129.121.128.131}"

# Port from name suffix
case "$CLUSTER_NAME" in
  *-infra) API_PORT=6443 ;;
  *-apps)  API_PORT=6444 ;;
  *-platform) API_PORT=6445 ;;
  *) echo "unknown role in $CLUSTER_NAME" >&2; exit 1 ;;
esac

HAS_KIND=0
if terraform state list 2>/dev/null | grep -qx "$TF_ADDR"; then
  HAS_KIND=1
fi

KIND_EXISTS=0
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  KIND_EXISTS=1
fi

echo "cluster=$CLUSTER_NAME kind_exists=$KIND_EXISTS tf_has_kind=$HAS_KIND addr=$TF_ADDR"

if [[ "$KIND_EXISTS" -eq 1 && "$HAS_KIND" -eq 0 ]]; then
  echo "IMPORT existing Kind into terraform (refuse delete)"
  # tehcyx/kind import id = cluster name
  terraform import -input=false "$TF_ADDR" "$CLUSTER_NAME"
elif [[ "$KIND_EXISTS" -eq 1 && "$HAS_KIND" -eq 1 ]]; then
  echo "already adopted — skip import"
elif [[ "$KIND_EXISTS" -eq 0 && "$HAS_KIND" -eq 0 ]]; then
  echo "Kind missing — terraform apply will create (ok)"
elif [[ "$KIND_EXISTS" -eq 0 && "$HAS_KIND" -eq 1 ]]; then
  echo "ERROR: TF thinks cluster exists but kind get clusters has no $CLUSTER_NAME" >&2
  echo "Do NOT auto-delete. Fix manually (kind create or state rm after explicit confirm)." >&2
  exit 2
fi

# Refresh SoT kubeconfig from Kind (keeps CA+client certs); rewrite public server
if [[ "$KIND_EXISTS" -eq 1 ]] || kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  KC="/data/am-state/kubeconfig.${CLUSTER_NAME}.yaml"
  kind get kubeconfig --name "$CLUSTER_NAME" >"$KC"
  python3 - "$KC" "$VPS_IP" "$API_PORT" <<'PY'
import sys
from pathlib import Path
kc_path, vps_ip, port = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = kc_path.read_text()
for old in (
    f"https://127.0.0.1:{port}",
    f"https://0.0.0.0:{port}",
    f"https://localhost:{port}",
):
    text = text.replace(old, f"https://{vps_ip}:{port}")
# never leave insecure-skip without CA after rewrite
kc_path.write_text(text)
print("rewrote", kc_path, "->", f"https://{vps_ip}:{port}")
PY
  chmod 600 "$KC"
  chown am-ops:am-ops "$KC" 2>/dev/null || true
  mkdir -p /home/am-ops/.asrax
  cp -f "$KC" "/home/am-ops/.asrax/$(basename "$KC")"
  chown am-ops:am-ops "/home/am-ops/.asrax/$(basename "$KC")" 2>/dev/null || true
  chmod 600 "/home/am-ops/.asrax/$(basename "$KC")" 2>/dev/null || true
fi

# DNAT for laptop/plugin reachability (host public IP → kind listen)
iptables -t nat -C PREROUTING -p tcp --dport "$API_PORT" -j DNAT --to-destination "127.0.0.1:${API_PORT}" 2>/dev/null || \
  iptables -t nat -A PREROUTING -p tcp --dport "$API_PORT" -j DNAT --to-destination "127.0.0.1:${API_PORT}" || true

echo "ADOPT_OK $CLUSTER_NAME"
