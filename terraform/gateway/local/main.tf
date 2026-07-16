# ==============================================================================
# LOCAL ENVIRONMENT: GATEWAY ENTRYPOINT
# ==============================================================================

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

module "gateway" {
  source = "./.."

  environment              = var.environment
  root_domain              = var.root_domain
  infra_namespace          = var.infra_namespace
  cloudflare_tunnel_id     = var.cloudflare_tunnel_id
  cloudflare_tunnel_secret = var.cloudflare_tunnel_secret
}
