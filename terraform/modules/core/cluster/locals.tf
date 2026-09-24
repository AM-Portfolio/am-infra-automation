locals {
  cluster_name = var.cluster_role == "obs" ? "am-obs" : "am-${var.env}-${var.cluster_role}"

  role_label = var.cluster_role == "obs" ? "observability" : var.cluster_role

  default_api_port = contains(["infra", "obs"], var.cluster_role) ? 6443 : (
    var.cluster_role == "apps" ? 6444 : 6445
  )
  api_server_port = var.api_server_port != null ? var.api_server_port : local.default_api_port

  default_node_shape = var.env == "prod" ? "two" : "one"
  node_shape         = var.node_shape != null ? var.node_shape : local.default_node_shape

  # obs is a single cluster on the obs host. env and role must agree.
  env_role_ok = (
    (var.env == "obs" && var.cluster_role == "obs") ||
    (var.env != "obs" && var.cluster_role != "obs")
  )

  # prod is two-node; other business tokens are one-node.
  node_shape_ok = (
    (var.env == "prod" && local.node_shape == "two") ||
    (var.env != "prod" && local.node_shape == "one")
  )

  api_port_ok = (
    (contains(["infra", "obs"], var.cluster_role) && local.api_server_port == 6443) ||
    (var.cluster_role == "apps" && local.api_server_port == 6444) ||
    (var.cluster_role == "platform" && local.api_server_port == 6445)
  )

  cp_patches = concat(
    [
      <<-EOT
      kind: InitConfiguration
      nodeRegistration:
        kubeletExtraArgs:
          node-labels: "role=${local.role_label}"
      EOT
    ],
    [
      <<-EOT
      kind: ClusterConfiguration
      etcd:
        local:
          extraArgs:
            heartbeat-interval: "500"
            election-timeout: "2500"
      EOT
    ],
    var.vps_ip != "" ? [
      <<-EOT
      kind: ClusterConfiguration
      apiServer:
        certSANs:
          - "${var.vps_ip}"
      EOT
    ] : []
  )

  worker_patches = [
    <<-EOT
    kind: JoinConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "role=${local.role_label}"
    EOT
  ]

  nodes = concat(
    [
      {
        role    = "control-plane"
        patches = local.cp_patches
      }
    ],
    local.node_shape == "two" ? [
      {
        role    = "worker"
        patches = local.worker_patches
      }
    ] : []
  )
}

check "env_role_pairing" {
  assert {
    condition     = local.env_role_ok
    error_message = "env=obs requires cluster_role=obs (name am-obs). Other envs cannot use cluster_role=obs."
  }
}

check "node_shape_for_env" {
  assert {
    condition     = local.node_shape_ok
    error_message = "prod must be node_shape=two. dev, dr, and obs must be node_shape=one."
  }
}

check "api_port_for_role" {
  assert {
    condition     = local.api_port_ok
    error_message = "infra/obs API must be 6443, apps 6444, platform 6445."
  }
}
