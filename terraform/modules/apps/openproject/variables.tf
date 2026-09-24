variable "namespace" {
  type    = string
  default = "openproject"
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
  default = "openproject"
}
variable "db_password" {
  type      = string
  sensitive = true
}
variable "db_schema" {
  type    = string
  default = "openproject"
}
variable "image" {
  type    = string
  default = "openproject/openproject:14"
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
  default = 30080
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
  default = "100m"
}
variable "cpu_limit" {
  type    = string
  default = "1000m"
}
variable "memory_request" {
  type    = string
  default = "512Mi"
}
variable "memory_limit" {
  type    = string
  default = "2Gi"
}
