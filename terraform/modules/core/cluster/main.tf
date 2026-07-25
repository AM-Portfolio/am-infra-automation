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

    # Node 1: Control plane + databases/infra services
    node {
      role = "control-plane"
      kubeadm_config_patches = concat(
        [
          <<-EOT
          kind: InitConfiguration
          nodeRegistration:
            kubeletExtraArgs:
              node-labels: "role=infra"
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
      extra_mounts {
        host_path      = "/mnt/am-infra/data"
        container_path = "/mnt/am-infra/data"
      }
      extra_mounts {
        host_path      = "/mnt/etcd-ram"
        container_path = "/var/lib/etcd"
      }
    }

    # Node 2: Microservices and applications
    node {
      role = "worker"
      kubeadm_config_patches = [
        <<-EOT
        kind: JoinConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "role=services"
        EOT
      ]
    }

    # Node 3: Observability stack (Prometheus, Grafana, Loki)
    node {
      role = "worker"
      kubeadm_config_patches = [
        <<-EOT
        kind: JoinConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "role=observability"
        EOT
      ]
    }
  }
}

output "kubeconfig" {
  value     = kind_cluster.this.kubeconfig
  sensitive = true
}
