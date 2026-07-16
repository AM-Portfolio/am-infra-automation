# ==============================================================================
# LOCAL ENVIRONMENT: PLATFORM ENTRYPOINT
# ==============================================================================

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

data "terraform_remote_state" "identity" {
  backend = "local"
  config = {
    path = "../../identity/local/terraform.tfstate"
  }
}

module "platform" {
  source = "./.."

  root_domain      = var.root_domain
  environment      = var.environment
  
  github_pat       = var.github_pat
  github_repo_url  = var.github_repo_url
  github_org_name  = var.github_org_name
  vps_pass         = var.vps_pass
}

