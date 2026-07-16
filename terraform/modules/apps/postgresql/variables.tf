variable "root_domain" {
  description = "The root domain (e.g., munish.org)"
  type        = string
}

variable "namespace" {
  description = "The target namespace to deploy to"
  type        = string
  default     = "infra"
}

variable "auth_flow_id" {
  description = "The ID of the default authentication flow"
  type        = string
  default     = null
}

variable "invalidation_flow_id" {
  description = "The ID of the Authentik invalidation flow"
  type        = string
  default     = null
}


variable "db_user" {
    type    = string
    default = "postgres"
}

variable "db_password" {
    type      = string
    sensitive = true
}

variable "db_name" {
    type    = string
    default = "postgres"
}

variable "pgadmin_user" {
    type    = string
    default = "admin@munish.org"
}

variable "pgadmin_password" {
    type      = string
    sensitive = true
}

variable "environment" {
  description = "The deployment environment (local, prod, etc.)"
  type        = string
  default     = "local"
}
