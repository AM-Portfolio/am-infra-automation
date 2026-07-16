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
  description = "The deployment environment (local, prod, etc.)"
  type        = string
  default     = "local"
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
