variable "namespace" {
  type    = string
  default = "temporal"
}

variable "environment" {
  type = string
}

variable "root_domain" {
  type = string
}

variable "db_host" {
  type = string
}

variable "db_name" {
  type        = string
  default     = "temporal"
  description = "Postgres database for Temporal default store (not the shared platform DB)."
}

variable "visibility_db_name" {
  type        = string
  default     = "temporal_visibility"
  description = "Postgres database for Temporal visibility store."
}

variable "db_user" {
  type    = string
  default = "temporal"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_schema" {
  type    = string
  default = "public"
}

variable "visibility_schema" {
  type    = string
  default = "public"
}

variable "chart_version" {
  type    = string
  default = "0.62.0"
}

variable "enable_gateway" {
  type    = bool
  default = true
}

variable "oidc_enabled" {
  type    = bool
  default = false
}

variable "node_port" {
  type    = number
  default = 30823
}

variable "gateway_same_cluster" {
  type    = bool
  default = false
}

variable "gateway_middleware_namespace" {
  type    = string
  default = "infra"
}

variable "server_cpu_request" {
  type    = string
  default = "100m"
}

variable "server_cpu_limit" {
  type    = string
  default = "500m"
}

variable "server_memory_request" {
  type    = string
  default = "256Mi"
}

variable "server_memory_limit" {
  type    = string
  default = "1Gi"
}

variable "web_cpu_request" {
  type    = string
  default = "50m"
}

variable "web_cpu_limit" {
  type    = string
  default = "200m"
}

variable "web_memory_request" {
  type    = string
  default = "128Mi"
}

variable "web_memory_limit" {
  type    = string
  default = "256Mi"
}
