# 0. CLUSTER PROVISIONING (The Foundation)
# Cluster name is dynamically derived from the environment:
#   local   → am-local
#   preprod → am-preprod
#   prod    → am-prod
module "cluster" {
  source             = "../modules/core/cluster"
  cluster_name       = "am-${var.environment}"
  config_output_path = var.kubeconfig_path != "" ? var.kubeconfig_path : "${path.module}/am-${var.environment}-config"
  vps_ip             = var.vps_ip
}
