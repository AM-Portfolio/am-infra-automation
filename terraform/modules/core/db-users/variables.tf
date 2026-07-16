variable "namespace" {
  description = "Kubernetes namespace for credential secrets"
  type        = string
  default     = "infra"
}

variable "infra_admins_group_id" {
  description = "Authentik group ID for infra-admins (to link DB admin accounts)"
  type        = string
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
  description = "Map of application PostgreSQL users to create"
  type = map(object({
    password = string
    database = string
  }))
  default   = {}
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
