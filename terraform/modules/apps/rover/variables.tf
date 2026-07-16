variable "namespace" {
  description = "The target namespace to deploy to"
  type        = string
  default     = "infra"
}

variable "environment" {
  type = string
}

variable "root_domain" {
  type = string
}
