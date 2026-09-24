# Phase 4h — Alloy log + metrics shipper on am-dev-infra (all NS → fleet Loki/Prom).
# Uses kubeconfig (cluster already exists); does not recreate Kind.
# Cross-cluster: HTTPS only.

provider "kubernetes" {
  config_path    = pathexpand("~/.asrax/kubeconfig.am-dev-infra.yaml")
  config_context = "kind-am-dev-infra"
}

provider "helm" {
  kubernetes {
    config_path    = pathexpand("~/.asrax/kubeconfig.am-dev-infra.yaml")
    config_context = "kind-am-dev-infra"
  }
}

locals {
  loki_push_url               = "https://loki.asrax.in/loki/api/v1/push"
  prometheus_remote_write_url = "https://prometheus.asrax.in/api/v1/write"
}

module "alloy_logs" {
  source = "../../../modules/core/alloy-logs"

  namespace                    = "monitoring"
  cluster_name                = "am-dev-infra"
  environment                 = "dev"
  loki_push_url               = local.loki_push_url
  prometheus_remote_write_url = local.prometheus_remote_write_url
}

output "alloy_namespace" {
  value = module.alloy_logs.namespace
}

output "alloy_loki_push_url" {
  value = local.loki_push_url
}

output "alloy_prometheus_remote_write_url" {
  value = local.prometheus_remote_write_url
}
