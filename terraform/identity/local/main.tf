# ==============================================================================
# LOCAL ENVIRONMENT: IDENTITY ENTRYPOINT
# ==============================================================================

terraform {
  backend "local" {}
}

data "terraform_remote_state" "foundation" {
  backend = "local"
  config = {
    path = "../../state/foundation.tfstate"
  }
}

locals {
  creds = data.terraform_remote_state.foundation.outputs.credentials
}

module "identity" {
  source = "./.."

  root_domain          = var.root_domain
  namespace_identity   = data.terraform_remote_state.foundation.outputs.identity_ns
  namespace_infra      = data.terraform_remote_state.foundation.outputs.infra_ns
  
  authentik_secret_key = "${local.creds.authentik_bootstrap}-secret-key"
  bootstrap_token      = local.creds.authentik_bootstrap
  postgres_password    = local.creds.authentik_postgres
  is_bootstrap         = var.authentik_token == ""
  
  am_auth_db_password      = var.am_auth_db_password
  am_market_db_password    = var.am_market_db_password
  am_market_mongo_password = var.am_market_mongo_password
}

# ==============================================================================
# BINDING OUTPUTS
# ==============================================================================

output "auth_flow_id" {
  value     = module.identity.auth_flow_id
  sensitive = true
}

output "invalidation_flow_id" {
  value     = module.identity.invalidation_flow_id
  sensitive = true
}

output "certificate_key_id" {
  value     = module.identity.certificate_key_id
  sensitive = true
}

output "property_mappings" {
  value     = module.identity.property_mappings
  sensitive = true
}

output "infra_admins_group_id" {
  value = module.identity.infra_admins_group_id
}
output "terraform_token" { 
    value     = module.identity.terraform_token 
    sensitive = true
}
