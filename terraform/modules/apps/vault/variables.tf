variable "namespace" {
  description = "The target namespace to deploy Vault into"
  type        = string
  default     = "vault"
}

variable "root_domain" {
  description = "The root domain (e.g., munish.org)"
  type        = string
}

variable "vault_node_port" {
  description = "The NodePort to expose Vault API on"
  type        = number
  default     = 30820
}

variable "auth_flow_id" {
  description = "The ID of the default authentication flow"
  type        = string
  default     = null
}

variable "certificate_key_id" {
  description = "The ID of the certificate signing key"
  type        = string
  default     = null
}

variable "property_mappings" {
  description = "List of OIDC scope mapping IDs"
  type        = list(string)
  default     = []
}


variable "invalidation_flow_id" {
  description = "The ID of the Authentik invalidation flow"
  type        = string
  default     = null
}

variable "watcher_poll_interval_seconds" {
  description = "How often (in seconds) the vault-unsealer-watcher pod checks Vault's seal status"
  type        = number
  default     = 15
}

variable "environment" {
  description = "The deployment environment (e.g., local, preprod, prod)"
  type        = string
  default     = "prod"
}

variable "vault_unseal_key" {
  description = "The unseal key provided as a bootstrap seed from .env or local environment"
  type        = string
  sensitive   = true
  default     = ""
}

variable "infra_namespace" {
  description = "Namespace where global middlewares are located"
  type        = string
  default     = "infra"
}
