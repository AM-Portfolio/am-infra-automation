variable "environment" {
  description = "Fleet env token. Must be the same as the kind-fleet/<env>/stores folder."
  type        = string

  validation {
    condition     = contains(["dev", "prod", "dr"], var.environment)
    error_message = "environment must be one of: dev, prod, dr. Never local or preprod."
  }
}
