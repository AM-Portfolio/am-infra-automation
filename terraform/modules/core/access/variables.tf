variable "root_domain" {
  description = "The primary domain name"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vault_oidc_client_secret" {
  description = "OIDC Client Secret for Vault"
  type        = string
  sensitive   = true
}

locals {
  domain_suffix = var.environment == "prod" ? "" : "-${var.environment}"
  traefik_host  = "traefik${local.domain_suffix}.${var.root_domain}"
  vault_host    = "vault${local.domain_suffix}.${var.root_domain}"
  authentik_host = "authentik${local.domain_suffix}.${var.root_domain}"
}
