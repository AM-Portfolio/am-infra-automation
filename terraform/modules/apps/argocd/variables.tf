variable "namespace" {
  type    = string
  default = "argocd"
}

variable "environment" {
  type = string
}

variable "root_domain" {
  type    = string
  default = "asrax.in"
}

variable "chart_version" {
  type    = string
  default = "10.8.0"
}

variable "server_cpu_request" {
  type    = string
  default = "50m"
}

variable "server_cpu_limit" {
  type    = string
  default = "500m"
}

variable "server_memory_request" {
  type    = string
  default = "128Mi"
}

variable "server_memory_limit" {
  type    = string
  default = "512Mi"
}

variable "controller_cpu_request" {
  type    = string
  default = "100m"
}

variable "controller_cpu_limit" {
  type    = string
  default = "1000m"
}

variable "controller_memory_request" {
  type    = string
  default = "256Mi"
}

variable "controller_memory_limit" {
  type    = string
  default = "1Gi"
}

variable "repo_server_cpu_request" {
  type    = string
  default = "50m"
}

variable "repo_server_cpu_limit" {
  type    = string
  default = "500m"
}

variable "repo_server_memory_request" {
  type    = string
  default = "128Mi"
}

variable "repo_server_memory_limit" {
  type    = string
  default = "512Mi"
}

variable "node_port" {
  type    = number
  default = 30443
}

variable "node_port_https" {
  description = "Must differ from node_port (chart defaults https to 30443)."
  type        = number
  default     = 30444
}

variable "enable_gateway" {
  type    = bool
  default = true
}

variable "gateway_same_cluster" {
  type    = bool
  default = false
}

variable "gateway_middleware_namespace" {
  type    = string
  default = "infra"
}

variable "oidc_issuer" {
  description = "Keycloak realm issuer URL, e.g. https://auth-dev.asrax.in/realms/am-realm"
  type        = string
  default     = ""
}

variable "oidc_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "enable_oidc_secret" {
  type    = bool
  default = false
}

variable "infra_api_server" {
  description = "Infra Kind API to enroll (e.g. https://127.0.0.1:6443). Apps API later in Phase 4."
  type        = string
  default     = "https://127.0.0.1:6443"
}

variable "oidc_enabled" {
  type    = bool
  default = false
}

variable "disable_local_admin" {
  description = "Disable Argo CD local admin password login (OIDC-only). Phase 10 / ZT-P1."
  type        = bool
  default     = false
}
