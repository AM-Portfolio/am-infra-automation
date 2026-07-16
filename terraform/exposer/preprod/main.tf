# ==============================================================================
# LOCAL ENVIRONMENT: EXPOSER ENTRYPOINT
# ==============================================================================

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

data "terraform_remote_state" "foundation" {
  backend = "local"
  config = {
    path = "../../foundation/local/terraform.tfstate"
  }
}

locals {
  kind_ip = "172.19.0.8" # Dynamically inspected Kind IP

  # This creates a PERMANENT bridge from the host to the cluster gateway
  port_forward_config = [
    # Core Gateway (Justice Fix)
    { name = "traefik-http",     host_port = 80,    target_host = local.kind_ip, target_port = 30080 },
    { name = "traefik-https",    host_port = 443,   target_host = local.kind_ip, target_port = 30443 },
    { name = "traefik-dashboard", host_port = 8088, target_host = local.kind_ip, target_port = 30990 },

    # Direct Access (Fallbacks & Databases)
    { name = "vault-root",       host_port = 8200,  target_host = local.kind_ip, target_port = 30820 },
    { name = "vault-ui",         host_port = 8201,  target_host = local.kind_ip, target_port = 30545 },
    { name = "authentik-api",    host_port = 9000,  target_host = local.kind_ip, target_port = 30900 },
    { name = "authentik-ui",     host_port = 9443,  target_host = local.kind_ip, target_port = 30080 },
    
    # 🐘 Databases (Exposed to Host + Cloud)
    { name = "postgres-main",    host_port = 5432,  target_host = local.kind_ip, target_port = 30432 },
    { name = "postgres-auth",    host_port = 5433,  target_host = local.kind_ip, target_port = 30543 },
    { name = "mongodb",          host_port = 27017, target_host = local.kind_ip, target_port = 30017 },
    { name = "redis",            host_port = 6379,  target_host = local.kind_ip, target_port = 30379 },
  ]
}

module "exposer" {
  source   = "./.."
  mappings = local.port_forward_config
}
