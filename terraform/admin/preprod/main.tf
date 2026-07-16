# ==============================================================================
# LOCAL ENVIRONMENT: ADMIN ENTRYPOINT
# ==============================================================================

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

module "admin" {
  source = "./.."

  root_domain    = var.root_domain
  environment    = "local"
  vault_enabled  = var.vault_enabled
  headlamp_token = var.headlamp_token
}
