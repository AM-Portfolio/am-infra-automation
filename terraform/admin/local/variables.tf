# ==============================================================================
# LOCAL ADMIN VARIABLES — Declarations for Orchestrator Inputs
# ==============================================================================

variable "root_domain" {
  description = "The primary domain name"
  type        = string
  default     = "munish.org"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "local"
}

variable "vault_enabled" {
  description = "Whether to attempt a Vault lookup. Set to false for initial bootstrap run."
  type        = bool
  default     = true
}

variable "headlamp_token" {
  description = "Baseline token for Headlamp (fished from .env)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "vault_root_token" {
  description = "Initial root token for Vault access"
  type        = string
  default     = ""
  sensitive   = true
}
