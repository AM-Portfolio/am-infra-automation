variable "root_domain" {
  description = "The primary domain name"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "local"
}

variable "headlamp_token" {
  description = "Baseline token for Headlamp (fallback)"
  type        = string
  default     = ""
  sensitive   = true
}
