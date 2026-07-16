# ==============================================================================
# Secret Resolver Module — Variables
# ==============================================================================

variable "vault_path" {
  description = "Path to the secret in Vault (e.g., local/infra/admin)"
  type        = string
  default     = ""
}

variable "vault_key" {
  description = "The specific key to retrieve from the Vault secret"
  type        = string
  default     = ""
}

variable "vault_enabled" {
  description = "Whether to attempt a Vault lookup. Set to false for initial bootstrap run."
  type        = bool
  default     = true
}

variable "k8s_secret_name" {
  description = "Name of the Kubernetes secret to check"
  type        = string
  default     = ""
}

variable "k8s_secret_namespace" {
  description = "Namespace of the Kubernetes secret"
  type        = string
  default     = "infra"
}

variable "k8s_secret_key" {
  description = "The specific key to retrieve from the K8s secret"
  type        = string
  default     = "token"
}

variable "fallback_value" {
  description = "The baseline value from .env or elsewhere"
  type        = string
  default     = ""
  sensitive   = true
}
