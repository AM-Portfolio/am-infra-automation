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
  default = "langfuse"
}
variable "db_password" {
  type      = string
  sensitive = true
}
variable "db_schema" {
  type    = string
  default = "langfuse"
}
variable "redis_host" { type = string }
variable "redis_password" {
  type      = string
  sensitive = true
}
variable "redis_db" {
  type    = number
  default = 0
}
variable "minio_endpoint" { type = string }
variable "minio_user" {
  type    = string
  default = "langfuse"
}
variable "minio_password" {
  type      = string
  sensitive = true
}
variable "minio_bucket" {
  type    = string
  default = "platform"
}
variable "chart_version" {
  type    = string
  default = "1.5.0"
}
variable "clickhouse_image" {
  type    = string
  default = "clickhouse/clickhouse-server:24.8"
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
  default = 30301
}
variable "gateway_same_cluster" {
  type    = bool
  default = false
}
variable "gateway_middleware_namespace" {
  type    = string
  default = "infra"
}
variable "web_cpu_request" {
  type    = string
  default = "100m"
}
variable "web_cpu_limit" {
  type    = string
  default = "500m"
}
variable "web_memory_request" {
  type    = string
  default = "512Mi"
}
variable "web_memory_limit" {
  type    = string
  default = "1Gi"
}
variable "clickhouse_cpu_request" {
  type    = string
  default = "100m"
}
variable "clickhouse_cpu_limit" {
  type    = string
  default = "1000m"
}
variable "clickhouse_memory_request" {
  type    = string
  default = "512Mi"
}
variable "clickhouse_memory_limit" {
  type    = string
  default = "2Gi"
}
