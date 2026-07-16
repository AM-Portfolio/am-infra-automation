variable "root_domain" {
  description = "The root domain (e.g., munish.org)"
  type        = string
}

variable "namespace" {
  description = "The target namespace to deploy to"
  type        = string
  default     = "infra"
}

variable "oidc_client_id" {
  description = "OIDC Client ID for Headlamp"
  type        = string
  default     = ""
}

variable "oidc_client_secret" {
  description = "OIDC Client Secret for Headlamp"
  type        = string
  sensitive   = true
  default     = ""
}
variable "issuer_url" {
  description = "OIDC Issuer URL (Authentik)"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Deployment environment (local/prod)"
  type        = string
  default     = "local"
}
