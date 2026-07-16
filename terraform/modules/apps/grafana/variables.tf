variable "root_domain" {
  description = "The root domain (e.g., munish.org)"
  type        = string
}

variable "namespace" {
  description = "The target namespace to deploy to"
  type        = string
  default     = "monitoring"
}

variable "environment" {
  description = "Deployment environment name"
  type        = string
  default     = "local"
}

variable "infra_namespace" {
  description = "The namespace where shared infrastructure (Traefik) lives"
  type        = string
  default     = "infra"
}


variable "grafana_admin_user" {
    type    = string
    default = "admin"
}

variable "grafana_admin_password" {
    type      = string
    sensitive = true
}

variable "grafana_client_id" {
    type      = string
}

variable "grafana_client_secret" {
    type      = string
    sensitive = true
}

variable "issuer_url" {
    type      = string
}


