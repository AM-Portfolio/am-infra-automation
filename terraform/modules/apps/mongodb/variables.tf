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
  description = "Enable OIDC for Mongo Express when an access layer exists. Fleet: false."
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


variable "mongo_root_user" {
  description = "Root username for MongoDB"
  type        = string
  default     = "admin"
}

variable "mongo_root_password" {
  description = "Root password for MongoDB"
  type        = string
  sensitive   = true
}

variable "cpu_request" {
  description = "MongoDB CPU request. Never rely on Helm/Bitnami default (unbounded / OOM)."
  type        = string
  default     = "50m"
}

variable "cpu_limit" {
  description = "MongoDB CPU limit."
  type        = string
  default     = "500m"
}

variable "memory_request" {
  description = "MongoDB memory request. Floor is 512Mi so WiredTiger does not start in an OOM corner."
  type        = string
  default     = "512Mi"
}

variable "memory_limit" {
  description = "MongoDB memory limit. 1Gi on laptop; raise on prod via wrapper."
  type        = string
  default     = "1Gi"
}

variable "storage" {
  description = "Mongo hostPath PV/PVC size."
  type        = string
  default     = "5Gi"
}

variable "wired_tiger_cache_gb" {
  description = "WiredTiger cache in GB. Must stay well under memory_limit (0.25 for 1Gi)."
  type        = string
  default     = "0.25"
}

/*
*/
