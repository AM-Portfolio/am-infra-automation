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
  description = "Fetch Authentik OIDC from Vault for Kafka UI. Fleet: false."
  type        = bool
  default     = true
}

variable "enable_gateway" {
  description = "Create Traefik IngressRoute. Fleet: false until Traefik exists."
  type        = bool
  default     = true
}

variable "cpu_request" {
  type    = string
  default = "50m"
}

variable "cpu_limit" {
  type    = string
  default = "500m"
}

variable "memory_request" {
  type    = string
  default = "512Mi"
}

variable "memory_limit" {
  type    = string
  default = "1Gi"
}

variable "storage" {
  type    = string
  default = "5Gi"
}

variable "advertised_host" {
  description = "External Kafka hostname. Empty = kafka-<env>.asrax.in (prod drops the env suffix)."
  type        = string
  default     = ""
}
