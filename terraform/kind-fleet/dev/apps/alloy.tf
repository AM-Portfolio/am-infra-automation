# Phase 4h — Alloy log + metrics shipper (all namespaces → fleet Loki/Prom).
# Agents NS is on this cluster; one DaemonSet covers apps + agents.
# Cross-cluster: HTTPS only (no platform-ip NodePort).

locals {
  loki_push_url               = "https://loki.asrax.in/loki/api/v1/push"
  prometheus_remote_write_url = "https://prometheus.asrax.in/api/v1/write"
}

module "alloy_logs" {
  source = "../../../modules/core/alloy-logs"

  namespace                   = "monitoring"
  cluster_name               = module.cluster.cluster_name
  environment                = local.env
  loki_push_url              = local.loki_push_url
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
