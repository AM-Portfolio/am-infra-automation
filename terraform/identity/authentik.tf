variable "namespace_identity" { type = string }
variable "namespace_infra" { type = string }
variable "authentik_secret_key" { type = string }
variable "bootstrap_token" { type = string }
variable "postgres_password" { type = string }
variable "is_bootstrap" { type = bool }

module "authentik_core" {
  source               = "../modules/core/authentik"
  environment          = var.environment
  root_domain          = var.root_domain
  namespace            = var.namespace_identity
  authentik_secret_key = var.authentik_secret_key
  bootstrap_token      = var.bootstrap_token
  postgres_password    = var.postgres_password
  admin_password       = "admin123"
  dev_password         = "dev123"
  is_bootstrap         = var.is_bootstrap
  
  proxy_provider_ids   = []
}

output "auth_flow_id" { value = module.authentik_core.auth_flow_id }
output "invalidation_flow_id" { value = module.authentik_core.invalidation_flow_id }
output "certificate_key_id" { value = module.authentik_core.certificate_key_id }
output "property_mappings" { value = module.authentik_core.property_mappings }
output "infra_admins_group_id" { value = module.authentik_core.infra_admins_group_id }
output "terraform_token" { value = module.authentik_core.terraform_token }
