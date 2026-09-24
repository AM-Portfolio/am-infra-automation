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
  description = "Enable OIDC for Influx UI when an access layer exists. Fleet: false."
  type        = bool
  default     = true
}

variable "enable_gateway" {
  description = "Create Traefik IngressRoute. Fleet: false until Traefik exists."
  type        = bool
  default     = true
}


variable "influx_user" {
    type    = string
    default = "admin"
}

variable "influx_password" {
    type      = string
    sensitive = true
}

variable "influx_token" {
    type      = string
    sensitive = true
}

variable "cpu_request" {
  description = "InfluxDB CPU request. Never rely on Helm default (unbounded / OOM)."
  type        = string
  default     = "50m"
}

variable "cpu_limit" {
  description = "InfluxDB CPU limit."
  type        = string
  default     = "500m"
}

variable "memory_request" {
  description = "InfluxDB memory request. 512Mi floor — chart default + 512Mi limit OOMs Influx 2."
  type        = string
  default     = "512Mi"
}

variable "memory_limit" {
  description = "InfluxDB memory limit. 1Gi on laptop so the process is not OOMKilled."
  type        = string
  default     = "1Gi"
}

variable "storage" {
  description = "Influx PVC size on first create. Do not raise this on a bound Kind standard claim (no expansion)."
  type        = string
  default     = "5Gi"
}

