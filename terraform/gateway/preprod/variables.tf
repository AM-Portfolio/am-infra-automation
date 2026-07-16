variable "environment" {
  type    = string
  default = "local"
}

variable "root_domain" {
  type    = string
  default = "munish.org"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API Token with administrative or zone permissions"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_email" {
  description = "Cloudflare Account Email"
  type        = string
  default     = ""
}

variable "infra_namespace" {
  type    = string
  default = "infra"
}

variable "vault_root_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "cloudflare_tunnel_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "cloudflare_tunnel_secret" {
  type      = string
  sensitive = true
  default   = ""
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
