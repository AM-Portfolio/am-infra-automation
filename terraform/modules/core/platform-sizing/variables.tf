variable "environment" {
  description = "Fleet env token. Must match kind-fleet/<env>/platform folder."
  type        = string

  validation {
    condition     = contains(["dev", "prod", "dr"], var.environment)
    error_message = "environment must be one of: dev, prod, dr. Never local or preprod."
  }
}
