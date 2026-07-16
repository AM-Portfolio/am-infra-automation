module "redis" {
  source         = "../modules/apps/redis"
  root_domain    = var.root_domain
  namespace      = var.namespace_infra
  redis_password = var.redis_password
  environment    = var.environment
}

module "kafka" {
  source       = "../modules/apps/kafka"
  root_domain  = var.root_domain
  namespace    = var.namespace_infra
  environment  = var.environment
}

# Vault has been extracted to terraform/vault/local — it is now Layer 2 of the
# pipeline and runs standalone, before this data-stores layer.
# Do NOT re-add module.vault here.
