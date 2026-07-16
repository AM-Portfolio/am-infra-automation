variable "root_domain" {
  description = "The root domain (e.g., munish.org)"
  type        = string
}

variable "namespace" {
  description = "The target namespace to deploy to"
  type        = string
  default     = "infra"
}

variable "environment" {
  description = "The deployment environment (local, prod, etc.)"
  type        = string
  default     = "local"
}


variable "influx_user" {
    type    = string
    default = "admin"
}

variable "influx_password" {
    type      = string
    sensitive = true
}

variable "influx_token" {
    type      = string
    sensitive = true
}

