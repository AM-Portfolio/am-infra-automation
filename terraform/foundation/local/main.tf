# ==============================================================================
# LOCAL ENVIRONMENT: FOUNDATION ENTRYPOINT
# ==============================================================================

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

module "foundation" {
  source = "./.."

  environment = var.environment
  root_domain = var.root_domain
  vps_ip      = var.vps_ip
  vps_ram_gb  = var.vps_ram_gb
}

# ==============================================================================
# BINDING OUTPUTS
# ==============================================================================

output "kubeconfig" {
  value     = module.foundation.kubeconfig
  sensitive = true
}

output "credentials" {
  value     = module.foundation.credentials
  sensitive = true
}

output "infra_ns" {
  value = module.foundation.infra_ns
}

output "identity_ns" {
  value = module.foundation.identity_ns
}

output "monitoring_ns" {
  value = module.foundation.monitoring_ns
}

output "vault_ns" {
  value = module.foundation.vault_ns
}
