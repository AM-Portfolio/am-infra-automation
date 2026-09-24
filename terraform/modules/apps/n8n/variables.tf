variable "namespace" {
  type    = string
  default = "n8n"
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
  default = "n8n"
}
variable "db_password" {
  type      = string
  sensitive = true
}
variable "db_schema" {
  type    = string
  default = "n8n"
}
variable "chart_version" {
  type    = string
  default = "1.11.0"
}
variable "storage_class" {
  type    = string
  default = "standard"
}
variable "encryption_key" {
  type      = string
  sensitive = true
  default   = ""
}
variable "image_repository" {
  type    = string
  default = "n8nio/n8n"
}
variable "image_tag" {
  type    = string
  default = "1.109.2"
}
variable "redis_host" {
  type = string
}
variable "redis_password" {
  type      = string
  sensitive = true
}
variable "redis_db" {
  type    = number
  default = 4
}
variable "worker_replicas" {
  type    = number
  default = 1
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
  default = 30567
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
  default = "1536Mi"
}
