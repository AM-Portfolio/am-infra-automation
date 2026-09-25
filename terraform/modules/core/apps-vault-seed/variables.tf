# Kind-fleet / apps Vault seed — reusable across env=dev|prod|dr.
# Writes mount "apps" KV v2: <env>/infra/* and <env>/services/<svc>
# Catalog: catalog/services.yaml (owned here — not am-gitops).

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

variable "env" {
  type        = string
  description = "Fleet env token (dev|prod|dr). Used in Vault paths and hostnames."
  validation {
    condition     = contains(["dev", "prod", "dr"], var.env)
    error_message = "env must be dev, prod, or dr."
  }
}

variable "domain" {
  type    = string
  default = "asrax.in"
}

variable "vault_mount" {
  type    = string
  default = "apps"
}

variable "postgres_user" { type = string }
variable "postgres_password" { type = string }
variable "postgres_db" {
  type    = string
  default = "postgres"
}
variable "mongo_user" { type = string }
variable "mongo_password" { type = string }
variable "redis_password" { type = string }
variable "influx_token" { type = string }
variable "influx_org" { type = string }
variable "influx_bucket" { type = string }
variable "influx_password" {
  type    = string
  default = ""
}

variable "keycloak_realm" {
  type    = string
  default = "am-realm"
}

variable "keycloak_admin_user" {
  type        = string
  default     = "admin"
  description = "Keycloak master admin username (must match platform Keycloak)."
}

variable "keycloak_admin_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Keycloak master admin password from platform apply. Required — refuse fleet placeholders."
}

variable "ui_base_url" {
  type        = string
  default     = ""
  description = "Override AUTH_UI_BASE_URL; default https://am-<env>.asrax.in (prod: https://am.asrax.in)."
}

variable "extra_service_data" {
  type        = map(map(string))
  default     = {}
  description = "Optional per-service key overrides merged last (e.g. real Upstox tokens)."
}
