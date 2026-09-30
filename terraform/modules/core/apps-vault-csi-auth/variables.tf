variable "env" {
  type = string
}

variable "apps_ns" {
  type = string
}

variable "agents_ns" {
  type = string
}

variable "kubernetes_host" {
  description = "Apps-cluster API URL reachable FROM the Vault pod (e.g. https://172.x.x.x:6443)"
  type        = string
}

variable "kubernetes_ca_cert_pem" {
  description = "Apps-cluster CA certificate PEM (not base64)"
  type        = string
  sensitive   = true
}

variable "auth_path" {
  type    = string
  default = "kubernetes-apps"
}

variable "role_name" {
  type    = string
  default = "am-backend-role"
}

variable "policy_name" {
  type    = string
  default = "am-apps-read"
}

variable "ghcr_username" {
  type    = string
  default = ""
}

variable "ghcr_token" {
  type      = string
  default   = ""
  sensitive = true
}

variable "create_pull_secrets" {
  description = "Create docker-registry pull secrets in apps + agents NS when ghcr_token is set"
  type        = bool
  default     = true
}

variable "extra_pull_secret_namespaces" {
  description = "Additional namespaces that get the same GHCR dockerconfigjson secrets (Vault bound_namespaces stay apps+agents only)"
  type        = list(string)
  default     = []
}
