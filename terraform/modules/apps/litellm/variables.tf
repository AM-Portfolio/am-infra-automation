variable "namespace" {
  type    = string
  default = "am-ai"
}
variable "environment" { type = string }
variable "root_domain" { type = string }
variable "db_host" { type = string }
variable "db_name" {
  type    = string
  default = "platform"
}
variable "db_user" {
  type    = string
  default = "litellm"
}
variable "db_password" {
  type      = string
  sensitive = true
}
variable "db_schema" {
  type    = string
  default = "litellm"
}
variable "image" {
  type    = string
  default = "ghcr.io/berriai/litellm-database:1.88.1"
}
variable "enable_gateway" {
  type    = bool
  default = true
}
variable "oidc_enabled" {
  type    = bool
  default = false
}
variable "master_key" {
  type      = string
  sensitive = true
  default   = ""
}
variable "node_port" {
  type    = number
  default = 30400
}
variable "gateway_same_cluster" {
  type    = bool
  default = false
}
variable "gateway_middleware_namespace" {
  type    = string
  default = "infra"
}
variable "cpu_request" {
  type    = string
  default = "50m"
}
variable "cpu_limit" {
  type    = string
  default = "500m"
}
variable "memory_request" {
  type    = string
  default = "512Mi"
}
variable "memory_limit" {
  type    = string
  default = "2Gi"
}
