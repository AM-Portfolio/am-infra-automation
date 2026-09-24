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
  description = "The deployment environment (local, preprod, prod, dev, dr, obs)"
  type        = string
  default     = "local"

  validation {
    condition     = contains(["local", "preprod", "prod", "dev", "dr", "obs"], var.environment)
    error_message = "environment must be one of: local, preprod, prod, dev, dr, obs."
  }
}

variable "oidc_enabled" {
  description = "Enable OIDC for Redis UI when an access layer exists. Fleet: false."
  type        = bool
  default     = true
}

variable "enable_gateway" {
  description = "Create Traefik IngressRoute. Fleet: false until Traefik exists."
  type        = bool
  default     = true
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


variable "redis_password" {
    type      = string
    sensitive = true
}

variable "cpu_request" {
  type    = string
  default = "50m"
}

variable "cpu_limit" {
  type    = string
  default = "200m"
}

variable "memory_request" {
  type    = string
  default = "256Mi"
}

variable "memory_limit" {
  type    = string
  default = "512Mi"
}

variable "storage" {
  type    = string
  default = "1Gi"
}

variable "redis_maxmemory" {
  description = "Redis maxmemory, e.g. 256mb. Must stay ≤ 75% of memory_limit."
  type        = string
  default     = "256mb"
}

