# 1. CORE KUBERNETES NAMESPACES
module "namespaces_core" {
  source      = "../modules/core/namespaces"
  environment = var.environment
}
