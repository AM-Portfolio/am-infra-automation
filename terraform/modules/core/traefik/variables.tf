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
  description = "The deployment environment (e.g., local, preprod, prod)"
  type        = string
  default     = "prod"
}
