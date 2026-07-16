variable "environment" {
  description = "Execution environment (local|preprod)"
  type        = string
}

variable "root_domain" {
  description = "The primary root domain (e.g., munish.org)"
  type        = string
}

variable "infra_namespace" {
  description = "The namespace for core infrastructure components (Traefik)"
  type        = string
  default     = "infra"
}

variable "cloudflare_tunnel_id" {
  description = "Existing Cloudflare Tunnel ID (Optional)"
  type        = string
  default     = ""
}

variable "cloudflare_tunnel_secret" {
  description = "Cloudflare Tunnel Secret (Optional)"
  type        = string
  default     = ""
}
