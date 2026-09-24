#!/usr/bin/env bash
# G1: create am-dr-{infra,apps,platform} on VPS3 (root only via break-glass-kind.sh).
# Ports: infra 6443, apps 6444, platform 6445. One-node (dr).
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "root only" >&2; exit 1; }

G1=/usr/local/sbin/break-glass-kind.sh
STATE=/data/am-state
CFG_DIR=/data/am-state/kind-configs
VPS_IP="${VPS_IP:-129.121.128.131}"
mkdir -p "$STATE" "$CFG_DIR" /root/.kube
chmod 755 /data /data/am-state

write_cfg() {
  local name="$1" port="$2" role="$3"
  cat >"$CFG_DIR/${name}.yaml" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: "127.0.0.1"
  apiServerPort: ${port}
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "role=${role}"
  - |
    kind: ClusterConfiguration
    etcd:
      local:
        extraArgs:
          heartbeat-interval: "500"
          election-timeout: "2500"
    apiServer:
      certSANs:
        - "${VPS_IP}"
        - "127.0.0.1"
        - "localhost"
EOF
}

create_one() {
  local name="$1" port="$2" role="$3"
  write_cfg "$name" "$port" "$role"
  if kind get clusters 2>/dev/null | grep -qx "$name"; then
    echo "EXISTS $name — skip create"
  else
    echo "==> G1 kind create $name :$port"
    "$G1" -- kind create cluster --name "$name" --config "$CFG_DIR/${name}.yaml"
  fi
  # Export kubeconfig to fleet path
  local kc="$STATE/kubeconfig.am-dr-${role}.yaml"
  # role mapping: infra/apps/platform match name suffix
  case "$name" in
    am-dr-infra) kc="$STATE/kubeconfig.am-dr-infra.yaml" ;;
    am-dr-apps) kc="$STATE/kubeconfig.am-dr-apps.yaml" ;;
    am-dr-platform) kc="$STATE/kubeconfig.am-dr-platform.yaml" ;;
  esac
  kind get kubeconfig --name "$name" >"$kc"
  chmod 0400 "$kc"
  # Also merge into root default for convenience (optional)
  KUBECONFIG="/root/.kube/config:$kc" kubectl config view --flatten > /root/.kube/config.merged 2>/dev/null || true
  if [[ -f /root/.kube/config.merged ]]; then
    mv /root/.kube/config.merged /root/.kube/config
    chmod 0400 /root/.kube/config
  fi
  echo "kubeconfig -> $kc"
  kubectl --kubeconfig="$kc" get nodes -o wide
}

export AM_OPS_REAL_KIND=/usr/local/libexec/am-real/kind
export AM_OPS_REAL_KUBECTL=/usr/local/libexec/am-real/kubectl
export PATH="/usr/local/libexec/am-real:/usr/local/bin:$PATH"

create_one am-dr-infra 6443 infra
create_one am-dr-apps 6444 apps
create_one am-dr-platform 6445 platform

echo "==> clusters:"
kind get clusters
ss -lnt | awk '$4 ~ /:644[345]$/ {print}' || true
echo "==> G1 log tail:"
tail -20 /var/log/am-break-glass.log || true
