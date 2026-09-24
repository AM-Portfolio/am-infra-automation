# Phase 4h — Alloy on platform cluster (monitoring + platform NS → same Loki/Prom).
# Same-cluster ClusterIP avoids CF hairpin; apps/infra Alloy use HTTPS FQDNs.

module "alloy_logs" {
  source = "../../../modules/core/alloy-logs"

  namespace         = local.namespace
  create_namespace = false
  cluster_name     = "am-dev-platform"
  environment      = local.env
  loki_push_url    = "http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push"
  # Same-cluster remote_write (receiver enabled on prometheus-server)
  prometheus_remote_write_url = "http://prometheus-server.monitoring.svc.cluster.local/api/v1/write"

  depends_on = [module.obs_stack, kubernetes_namespace_v1.monitoring]
}
