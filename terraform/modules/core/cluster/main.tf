# ==============================================================================
# KinD Cluster Provisioning
# ==============================================================================
# Declaratively manages the Kubernetes cluster on the VPS.
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
  name           = var.cluster_name
  wait_for_ready = true
  
  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    networking {
      api_server_address = "127.0.0.1"
      api_server_port    = 6443
    }

    # 1. CORE CONTROL PLANE
    node {
      role = "control-plane"
      kubeadm_config_patches = var.vps_ip != "" ? [
        <<-EOT
        kind: ClusterConfiguration
        apiServer:
          certSANs:
            - "${var.vps_ip}"
        EOT
      ] : []
      extra_mounts {
        host_path      = "/mnt/am-infra/data"
        container_path = "/mnt/am-infra/data"
      }
    }
  }
}

output "kubeconfig" {
  value     = kind_cluster.this.kubeconfig
  sensitive = true
}

output "endpoint" {
  value = kind_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  value = kind_cluster.this.cluster_ca_certificate
}

output "client_certificate" {
  value = kind_cluster.this.client_certificate
}

output "client_key" {
  value = kind_cluster.this.client_key
}
