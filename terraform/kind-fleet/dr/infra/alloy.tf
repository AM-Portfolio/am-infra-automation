# Phase 6 — Alloy on am-dr-infra (all NS → bare Loki/Prom).
# Uses kubeconfig (cluster already exists); does not recreate Kind.
# Apply on VPS3: terraform apply -target=module.alloy_logs

provider "kubernetes" {
  alias          = "alloy"
  config_path    = "/data/am-state/kubeconfig.am-dr-infra.yaml"
  config_context = "kind-am-dr-infra"
}

provider "helm" {
  alias = "alloy"
  kubernetes {
    config_path    = "/data/am-state/kubeconfig.am-dr-infra.yaml"
    config_context = "kind-am-dr-infra"
  }
}

locals {
  alloy_loki_push_url               = "https://loki.asrax.in/loki/api/v1/push"
  alloy_prometheus_remote_write_url = "https://prometheus.asrax.in/api/v1/write"
}

module "alloy_logs" {
  source = "../../../modules/core/alloy-logs"

  providers = {
    kubernetes = kubernetes.alloy
    helm       = helm.alloy
  }

  namespace                    = "monitoring"
  cluster_name                = "am-dr-infra"
  environment                 = "dr"
  vps                         = "vps-dr"
  vps_name                    = "VPS_DR"
  vps_ip                      = "129.121.128.131"
  loki_push_url               = local.alloy_loki_push_url
  prometheus_remote_write_url = local.alloy_prometheus_remote_write_url
}

output "alloy_namespace" {
  value = module.alloy_logs.namespace
}

output "alloy_loki_push_url" {
  value = local.alloy_loki_push_url
}

output "alloy_prometheus_remote_write_url" {
  value = local.alloy_prometheus_remote_write_url
}
