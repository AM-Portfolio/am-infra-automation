# Phase 6 — Alloy log + metrics shipper (apps + agents → bare Loki/Prom).
# Cross-cluster: HTTPS only.

locals {
  loki_push_url               = "https://loki.asrax.in/loki/api/v1/push"
  prometheus_remote_write_url = "https://prometheus.asrax.in/api/v1/write"
}

module "alloy_logs" {
  source = "../../../modules/core/alloy-logs"

  namespace                    = "monitoring"
  cluster_name                = module.cluster.cluster_name
  environment                 = local.env
  vps                         = "vps-prod"
  vps_name                    = "VPS_PROD"
  vps_ip                      = "203.174.22.129"
  loki_push_url               = local.loki_push_url
  prometheus_remote_write_url = local.prometheus_remote_write_url

  depends_on = [
    module.cluster,
    kubernetes_namespace.am_apps,
    kubernetes_namespace.am_agents,
  ]
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
