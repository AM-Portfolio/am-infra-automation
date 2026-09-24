variable "root_domain" {
  description = "The root domain (e.g., munish.org)"
  type        = string
}

variable "namespace" {
  description = "The target namespace to deploy (e.g., infra)"
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

variable "enable_gateway" {
  description = "Create Traefik IngressRoute. Fleet: false until Traefik exists."
  type        = bool
  default     = true
}

variable "image" {
  description = "MinIO server image. Docker Hub minio/minio:latest is gone; use Quay."
  type        = string
  default     = "quay.io/minio/minio:RELEASE.2025-04-22T22-12-26Z"
}

variable "minio_root_user" {
  description = "Root user for MinIO (Access Key)"
  type        = string
  default     = "minioadmin"
}

variable "minio_root_password" {
  description = "Root password for MinIO (Secret Key)"
  type        = string
  sensitive   = true
}

# OIDC Settings (Injected after Access layer run)
variable "oidc_enabled" {
  type    = bool
  default = false
}

variable "oidc_client_id" {
  type    = string
  default = ""
}

variable "oidc_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "oidc_issuer_url" {
  type    = string
  default = ""
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
  default = "256Mi"
}

variable "memory_limit" {
  type    = string
  default = "512Mi"
}

variable "storage" {
  type    = string
  default = "5Gi"
}
