# LEGACY — do not apply this stack for the Kind fleet.
# Fleet Kind lives in terraform/kind-fleet/{dev,prod,dr,obs}/.
# The cluster module now computes am-<env>-<role> / am-obs and rejects
# local, preprod, hostbet-vps. This file used to name am-local / am-preprod.
#
# module "cluster" {
#   source             = "../modules/core/cluster"
#   cluster_name       = "am-${var.environment}"  # refused
#   config_output_path = var.kubeconfig_path != "" ? var.kubeconfig_path : "${path.module}/am-${var.environment}-config"
#   vps_ip             = var.vps_ip
# }
