variable "namespace" {
  description = "Kubernetes namespace for credential secrets"
  type        = string
  default     = "infra"
}

variable "infra_admins_group_id" {
  description = "Authentik group ID for infra-admins (to link DB admin accounts). Empty skips Authentik."
  type        = string
  default     = ""
}

variable "shared_database" {
  description = "When set, create this one Postgres/Mongo database and give each app its own user+schema. Empty keeps one-DB-per-app."
  type        = string
  default     = ""
}

variable "provision_via" {
  description = "provider = postgresql/atlas resources (legacy). job = in-cluster Job (fleet; no host DB driver)."
  type        = string
  default     = "provider"

  validation {
    condition     = contains(["provider", "job"], var.provision_via)
    error_message = "provision_via must be provider or job."
  }
}

variable "enable_vault_secrets" {
  description = "Write db-user creds to Vault. Fleet: false until Vault is up."
  type        = bool
  default     = true
}

variable "enable_authentik" {
  description = "Register DBA users in Authentik. Fleet: false."
  type        = bool
  default     = true
}

variable "db_host" {
  description = "Host written into app secrets (DNS-only name, not localhost)."
  type        = string
  default     = "postgresql.infra.svc.cluster.local"
}

variable "mongo_host" {
  type    = string
  default = "mongodb.infra.svc.cluster.local"
}

variable "postgres_admin_secret" {
  description = "K8s secret with POSTGRES_USER / POSTGRES_PASSWORD for the in-cluster job."
  type        = string
  default     = "postgresql-secret"
}

variable "mongo_admin_secret" {
  type    = string
  default = "mongodb"
}

variable "redis_admin_secret" {
  type    = string
  default = "redis"
}

variable "minio_admin_secret" {
  type    = string
  default = "minio-secret"
}

variable "mongo_root_user" {
  type    = string
  default = "admin"
}

variable "mongo_root_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "redis_admin_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "redis_users" {
  description = "ACL users on the one Redis instance. Map: name => { password }"
  type = map(object({
    password = string
  }))
  default = {}
}

variable "minio_users" {
  description = "MinIO access keys on the one MinIO. Map: name => { password, prefix }"
  type = map(object({
    password = string
    prefix   = optional(string, "")
  }))
  default = {}
}

variable "mongodb_project_id" {
  description = "MongoDB Atlas Project ID (leave empty if using self-hosted)"
  type        = string
  default     = ""
}

# ------------------------------------------------------------------------------
# PostgreSQL App Users
# Map of: app-name => { password, database }
# Example:
#   postgresql_app_users = {
#     "am-auth"   = { password = "...", database = "auth_db" }
#     "am-market" = { password = "...", database = "market_db" }
#   }
# ------------------------------------------------------------------------------
variable "postgresql_app_users" {
  description = "Map of application PostgreSQL users. In shared_database mode, schemas isolate the user; set database + createdb for apps (e.g. Lago) that need a dedicated DB and Rails db:create."
  type = map(object({
    password  = string
    database  = optional(string, "")
    schemas   = optional(list(string), [])
    createdb  = optional(bool, false)
  }))
  default = {}
}

# ------------------------------------------------------------------------------
# MongoDB App Users
# Map of: app-name => { password, database, role }
# ------------------------------------------------------------------------------
variable "mongodb_app_users" {
  description = "Map of application MongoDB users to create"
  type = map(object({
    password = string
    database = string
    role     = string
  }))
  default   = {}
}

# ------------------------------------------------------------------------------
# Authentik DB Admin Accounts
# These are real humans who are granted DB admin access via Authentik SSO
# Map of: username => { display_name, email, databases }
# ------------------------------------------------------------------------------
variable "db_admin_accounts" {
  description = "Map of human DBA accounts to register in Authentik"
  type = map(object({
    display_name = string
    email        = string
    databases    = list(string)
  }))
  default = {}
}
