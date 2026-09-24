variable "env" {
  description = "Fleet environment (dev, prod, dr)"
  type        = string

  validation {
    condition     = contains(["dev", "prod", "dr"], var.env)
    error_message = "env must be one of: dev, prod, dr."
  }
}

variable "domain" {
  description = "Public DNS domain"
  type        = string
  default     = "asrax.in"
}
