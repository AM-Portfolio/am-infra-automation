variable "environment" {
  description = "Deployment environment (e.g., local, preprod, prod)"
  type        = string
}

variable "root_domain" {
  description = "The root domain (e.g., munish.org)"
  type        = string
}

variable "namespace" {
  description = "The target namespace to deploy to"
  type        = string
  default     = "identity"
}

variable "authentik_secret_key" {
    type      = string
    sensitive = true
}

variable "bootstrap_token" {
    type      = string
    sensitive = true
}

variable "postgres_password" {
    type      = string
    sensitive = true
}

variable "admin_password" {
    type      = string
    sensitive = true
}

variable "dev_password" {
    type      = string
    sensitive = true
}

variable "proxy_provider_ids" {
  description = "A dynamic list of Authentik Proxy IDs to be injected automatically into the Outpost"
  type        = list(string)
}

output "terraform_automation_token" {
  value     = authentik_token.terraform.key
  sensitive = true
}
variable "is_bootstrap" {
  description = "Set to true to skip data source lookups during initial install"
  type        = bool
  default     = false
}
