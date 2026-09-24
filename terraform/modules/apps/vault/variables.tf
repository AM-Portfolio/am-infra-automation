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

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = ""
}

variable "injector_enabled" {
  description = "Enable Vault Agent Injector. Fleet: false (CSI later on apps)."
  type        = bool
  default     = true
}

variable "csi_enabled" {
  description = "Enable Vault CSI provider. Fleet infra: false."
  type        = bool
  default     = true
}

variable "service_type" {
  description = "Vault server Service type. Fleet: ClusterIP."
  type        = string
  default     = "NodePort"
}

variable "ui_service_type" {
  description = "Vault UI Service type. Fleet: ClusterIP."
  type        = string
  default     = "NodePort"
}

variable "enable_unsealer" {
  description = "Run the bash local-exec unsealer. Fleet on Windows: false."
  type        = bool
  default     = true
}

variable "enable_watcher" {
  description = "Deploy the in-cluster unseal watcher. Fleet: false until unseal keys exist."
  type        = bool
  default     = true
}

variable "enable_host_aliases" {
  description = "Add Authentik hostAliases on the Vault pod. Fleet: false."
  type        = bool
  default     = true
}

variable "enable_gateway" {
  description = "Create Traefik IngressRoute for Vault UI/API. Requires Phase 2 edge first."
  type        = bool
  default     = false
}

variable "cpu_request" {
  type    = string
  default = "50m"
}

variable "cpu_limit" {
  type    = string
  default = "200m"
}

variable "memory_request" {
  type    = string
  default = "128Mi"
}

variable "memory_limit" {
  type    = string
  default = "256Mi"
}
