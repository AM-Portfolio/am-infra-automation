# ==============================================================================
# ACCESS LAYER — Local Environment
# Configures SSO bindings for Traefik and Vault
# ==============================================================================

module "access" {
  source      = "../../modules/core/access"
  root_domain              = var.root_domain
  environment              = var.environment
  vault_oidc_client_secret = var.vault_oidc_client_secret
}
