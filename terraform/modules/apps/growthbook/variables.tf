variable "namespace" {
  type    = string
  default = "growthbook"
}
variable "environment" { type = string }
variable "root_domain" { type = string }
variable "mongo_host" { type = string }
variable "mongo_db" {
  type    = string
  default = "platform"
}
variable "mongo_user" {
  type    = string
  default = "growthbook"
}
variable "mongo_password" {
  type      = string
  sensitive = true
}
variable "chart_version" {
  type    = string
  # Match am-infra kind-am-preprod lab (k8s/growthbook/values-lab.yaml).
  default = "4.4.0"
}
variable "image_tag" {
  type    = string
  default = "4.4.0"
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
  default = 30300
}
variable "gateway_same_cluster" {
  type    = bool
  default = false
}
variable "gateway_middleware_namespace" {
  type    = string
  default = "infra"
}
variable "frontend_cpu_request" {
  type    = string
  default = "100m"
}
variable "frontend_cpu_limit" {
  type    = string
  default = "750m"
}
variable "frontend_memory_request" {
  type    = string
  default = "512Mi"
}
variable "frontend_memory_limit" {
  type    = string
  default = "1Gi"
}
variable "backend_cpu_request" {
  type    = string
  default = "100m"
}
variable "backend_cpu_limit" {
  type    = string
  default = "750m"
}
variable "backend_memory_request" {
  type    = string
  default = "512Mi"
}
variable "backend_memory_limit" {
  type    = string
  default = "1Gi"
}
