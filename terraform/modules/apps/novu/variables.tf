variable "namespace" {
  type    = string
  default = "notification"
}
variable "environment" {
  type = string
}
variable "root_domain" {
  type = string
}
variable "chart_path" {
  type        = string
  default     = ""
  description = "Path to am-platform automation/helm/novu. Empty = sibling checkout."
}
variable "mongo_host" {
  type = string
}
variable "mongo_db" {
  type    = string
  default = "novu"
}
variable "mongo_user" {
  type    = string
  default = "admin"
}
variable "mongo_password" {
  type      = string
  sensitive = true
}
variable "redis_host" {
  type = string
}
variable "redis_password" {
  type      = string
  sensitive = true
}
variable "novu_secret_key" {
  type      = string
  sensitive = true
  default   = ""
}
variable "jwt_secret" {
  type      = string
  sensitive = true
  default   = ""
}
variable "storage_key" {
  type      = string
  sensitive = true
  default   = ""
}
variable "enable_gateway" {
  type    = bool
  default = true
}
variable "node_port" {
  type    = number
  default = 30420
}
variable "gateway_same_cluster" {
  type    = bool
  default = false
}
variable "gateway_middleware_namespace" {
  type    = string
  default = "infra"
}
variable "api_cpu_request" {
  type    = string
  default = "50m"
}
variable "api_cpu_limit" {
  type    = string
  default = "500m"
}
variable "api_memory_request" {
  type    = string
  default = "128Mi"
}
variable "api_memory_limit" {
  type    = string
  default = "512Mi"
}
variable "worker_cpu_request" {
  type    = string
  default = "50m"
}
variable "worker_cpu_limit" {
  type    = string
  default = "500m"
}
variable "worker_memory_request" {
  type    = string
  default = "128Mi"
}
variable "worker_memory_limit" {
  type    = string
  default = "512Mi"
}
variable "web_cpu_request" {
  type    = string
  default = "50m"
}
variable "web_cpu_limit" {
  type    = string
  default = "250m"
}
variable "web_memory_request" {
  type    = string
  default = "64Mi"
}
variable "web_memory_limit" {
  type    = string
  default = "256Mi"
}
variable "ws_cpu_request" {
  type    = string
  default = "50m"
}
variable "ws_cpu_limit" {
  type    = string
  default = "250m"
}
variable "ws_memory_request" {
  type    = string
  default = "64Mi"
}
variable "ws_memory_limit" {
  type    = string
  default = "256Mi"
}
