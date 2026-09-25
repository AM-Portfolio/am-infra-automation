# ==============================================================================
# KinD cluster — fleet names are computed, never am-preprod / am-local
# ==============================================================================

terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.2.0"
    }
  }
}

resource "kind_cluster" "this" {
  name           = local.cluster_name
  wait_for_ready = true

  lifecycle {
    precondition {
      condition     = local.env_role_ok
      error_message = "env=obs requires cluster_role=obs (name am-obs). Other envs cannot use cluster_role=obs."
    }
    precondition {
      condition     = local.node_shape_ok
      error_message = "Serve-first: prod infra = node_shape=two; prod apps/platform = one; dev/dr/obs = one."
    }
    precondition {
      condition     = local.api_port_ok
      error_message = "infra/obs API must be 6443, apps 6444, platform 6445."
    }
    precondition {
      condition     = !contains(["am-preprod", "am-local"], local.cluster_name)
      error_message = "Refusing Kind name am-preprod or am-local."
    }
  }

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    networking {
      api_server_address = var.api_server_address
      api_server_port    = local.api_server_port
    }

    dynamic "node" {
      for_each = local.nodes
      content {
        role                   = node.value.role
        kubeadm_config_patches = node.value.patches

        dynamic "extra_mounts" {
          for_each = node.value.role == "control-plane" && var.enable_data_mount ? [1] : []
          content {
            host_path      = var.data_host_path
            container_path = "/mnt/am-infra/data"
          }
        }

        dynamic "extra_mounts" {
          for_each = node.value.role == "control-plane" && var.enable_etcd_ram_mount ? [1] : []
          content {
            host_path      = var.etcd_ram_host_path
            container_path = "/var/lib/etcd"
          }
        }
      }
    }
  }
}

output "kubeconfig" {
  value     = kind_cluster.this.kubeconfig
  sensitive = true
}
