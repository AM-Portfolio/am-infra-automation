variable "namespace" {
  type    = string
  default = "billing"
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
  type    = string
  default = "platform"
}

variable "db_user" {
  type    = string
  default = "lago"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_schema" {
  type    = string
  default = "lago"
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
  default = 3
}

variable "chart_version" {
  type    = string
  default = "1.28.0"
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
  default = 30830
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
  default = "200m"
}

variable "api_cpu_limit" {
  type    = string
  default = "1000m"
}

variable "api_memory_request" {
  type    = string
  default = "512Mi"
}

variable "api_memory_limit" {
  type    = string
  default = "2Gi"
}

variable "front_cpu_request" {
  type    = string
  default = "50m"
}

variable "front_cpu_limit" {
  type    = string
  default = "500m"
}

variable "front_memory_request" {
  type    = string
  default = "256Mi"
}

variable "front_memory_limit" {
  type    = string
  default = "1Gi"
}
