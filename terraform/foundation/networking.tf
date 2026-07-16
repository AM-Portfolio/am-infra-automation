# 1. CORE KUBERNETES NAMESPACES
module "namespaces_core" {
  source      = "../modules/core/namespaces"
  environment = var.environment
}


# 2. CORE NETWORKING & GATEWAY
module "traefik_core" {
  source      = "../modules/core/traefik"
  root_domain = var.root_domain
  environment = var.environment
  namespace   = module.namespaces_core.infra_ns
}
