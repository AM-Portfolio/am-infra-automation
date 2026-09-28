# Phase 6 — Alloy on am-prod-infra (all NS → bare Loki/Prom).
# Uses kubeconfig (cluster already exists); does not recreate Kind.
# Apply on VPS1: terraform apply -target=module.alloy_logs

provider "kubernetes" {
  alias          = "alloy"
  config_path    = "/data/am-state/kubeconfig.am-prod-infra.yaml"
  config_context = "kind-am-prod-infra"
}

provider "helm" {
  alias = "alloy"
  kubernetes {
    config_path    = "/data/am-state/kubeconfig.am-prod-infra.yaml"
    config_context = "kind-am-prod-infra"
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
  cluster_name                = "am-prod-infra"
  environment                 = "prod"
  vps                         = "vps-prod"
  vps_name                    = "VPS_PROD"
  vps_ip                      = "203.174.22.129"
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
