variable "root_domain" {
  description = "The primary domain name for the infrastructure services"
  type        = string
  default     = "munish.org"
}

variable "environment" {
  description = "Deployment environment name"
  type        = string
  default     = "preprod"
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "/data/am-state/am-preprod-config"
}

variable "kubeconfig_context" {
  description = "Kubernetes context to use"
  type        = string
  default     = "am-preprod"
}

variable "vault_root_token" {
  description = "Root token for Vault provider authentication"
  type        = string
  sensitive   = true
  default     = ""
}

variable "authentik_token" {
  description = "API Token for Authentik provider authentication"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vault_oidc_client_secret" {
  description = "OIDC Client Secret for Vault"
  type        = string
  sensitive   = true
  default     = "vault_oidc_secret_change_me_in_prod" 
}
