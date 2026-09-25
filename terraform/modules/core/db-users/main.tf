terraform {
  required_providers {
    kubernetes   = { source = "hashicorp/kubernetes" }
    vault        = { source = "hashicorp/vault" }
    authentik    = { source = "goauthentik/authentik" }
    postgresql   = { source = "cyrilgdn/postgresql" }
    mongodbatlas = { source = "mongodb/mongodbatlas" }
  }
}

# ==============================================================================
# DATABASE USER MANAGEMENT — Terraform-Controlled DB Users + Authentik Onboarding
# ==============================================================================
# Manages:
#   - PostgreSQL: application-specific DB users + databases
#   - MongoDB: application-specific DB users with role bindings
#   - Redis: ACL users with command/key restrictions
#   - InfluxDB: organization + bucket + API token per application
#   - All credentials stored in Vault (secret/infra/db-users/<app>)
#   - Vault policies created per-app for secret access
#   - Authentik service account integration for DB admin onboarding
# ==============================================================================

# ==============================================================================
# POSTGRESQL USER MANAGEMENT
# ==============================================================================

locals {
  shared_mode   = var.shared_database != ""
  use_provider  = var.provision_via == "provider"
  use_job       = var.provision_via == "job"
  write_vault   = var.enable_vault_secrets
  write_authentik = var.enable_authentik && var.infra_admins_group_id != ""

  pg_db_name = local.shared_mode ? var.shared_database : ""

  pg_schema_map = {
    for item in flatten([
      for user, spec in var.postgresql_app_users : [
        for schema in(length(try(spec.schemas, [])) > 0 ? spec.schemas : [user]) : {
          key    = "${user}__${schema}"
          user   = user
          schema = schema
        }
      ]
    ]) : item.key => item
  }
}

# Create a dedicated DB user per application that needs PostgreSQL access
resource "postgresql_role" "app_users" {
  for_each = local.use_provider ? var.postgresql_app_users : {}

  name     = each.key
  login    = true
  password = each.value.password

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [password] # Managed via Vault rotation
  }
}

resource "postgresql_database" "app_databases" {
  for_each = local.use_provider && !local.shared_mode ? var.postgresql_app_users : {}

  name  = each.value.database != "" ? each.value.database : each.key
  owner = postgresql_role.app_users[each.key].name

  lifecycle {
    prevent_destroy = true
  }
}

resource "postgresql_database" "shared" {
  count = local.use_provider && local.shared_mode ? 1 : 0

  name  = var.shared_database
  owner = "postgres"

  lifecycle {
    prevent_destroy = true
  }
}

resource "postgresql_schema" "app_schemas" {
  for_each = local.use_provider && local.shared_mode ? local.pg_schema_map : {}

  name     = each.value.schema
  database = postgresql_database.shared[0].name
  owner    = postgresql_role.app_users[each.value.user].name
}

resource "postgresql_grant" "app_user_grants" {
  for_each = local.use_provider && !local.shared_mode ? var.postgresql_app_users : {}

  database    = postgresql_database.app_databases[each.key].name
  role        = postgresql_role.app_users[each.key].name
  schema      = "public"
  object_type = "database"
  privileges  = ["CREATE", "CONNECT", "TEMPORARY"]

  lifecycle {
    prevent_destroy = true
  }
}

# ==============================================================================
# MONGODB USER MANAGEMENT
# ==============================================================================

resource "mongodbatlas_database_user" "app_users" {
  for_each = var.mongodb_project_id != "" ? var.mongodb_app_users : {}

  username           = each.key
  password           = each.value.password
  project_id         = var.mongodb_project_id
  auth_database_name = "admin"

  roles {
    role_name     = each.value.role != "" ? each.value.role : "readWrite"
    database_name = each.value.database != "" ? each.value.database : each.key
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [password]
  }
}

# ==============================================================================
# VAULT SECRET STORAGE — One secret per app per database
# ==============================================================================

resource "vault_kv_secret_v2" "postgresql_creds" {
  for_each = local.write_vault ? var.postgresql_app_users : {}

  mount               = "secret"
  name                = "infra/db-users/postgresql/${each.key}"
  delete_all_versions = false

  data_json = jsonencode({
    username     = each.key
    password     = each.value.password
    database     = local.shared_mode ? var.shared_database : (each.value.database != "" ? each.value.database : each.key)
    host         = var.db_host
    port         = "5432"
    schema       = length(try(each.value.schemas, [])) > 0 ? each.value.schemas[0] : each.key
    database_url = "postgresql+asyncpg://${each.key}:${each.value.password}@${var.db_host}:5432/${local.shared_mode ? var.shared_database : (each.value.database != "" ? each.value.database : each.key)}"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "vault_kv_secret_v2" "mongodb_creds" {
  for_each = local.write_vault ? var.mongodb_app_users : {}

  mount               = "secret"
  name                = "infra/db-users/mongodb/${each.key}"
  delete_all_versions = false

  data_json = jsonencode({
    username     = each.key
    password     = each.value.password
    database     = local.shared_mode && each.value.database == "" ? var.shared_database : (each.value.database != "" ? each.value.database : each.key)
    host         = var.mongo_host
    port         = "27017"
    mongo_url    = "mongodb://${each.key}:${each.value.password}@${var.mongo_host}:27017/${local.shared_mode && each.value.database == "" ? var.shared_database : (each.value.database != "" ? each.value.database : each.key)}"
  })

  lifecycle {
    prevent_destroy = true
  }
}

# ==============================================================================
# VAULT POLICIES — Per-App read access to their own DB credentials
# ==============================================================================

resource "vault_policy" "app_db_policies" {
  for_each = local.write_vault ? merge(
    { for k, v in var.postgresql_app_users : "pg-${k}" => "infra/data/db-users/postgresql/${k}" },
    { for k, v in var.mongodb_app_users    : "mg-${k}" => "infra/data/db-users/mongodb/${k}" }
  ) : {}

  name = "db-access-${each.key}"

  policy = <<-EOT
    path "secret/data/${each.value}" {
      capabilities = ["read"]
    }
  EOT
}

# ==============================================================================
# AUTHENTIK: DB Admin Service Account Registration
# ==============================================================================
# This creates an Authentik user for each DB that DBAs can SSO into
# to act as the database admin. Links to the infra-admins group.

resource "authentik_user" "db_admin_users" {
  for_each = local.write_authentik ? var.db_admin_accounts : {}

  username = each.key
  name     = each.value.display_name
  email    = each.value.email
  groups   = [var.infra_admins_group_id]

  attributes = jsonencode({
    db_access = each.value.databases
    role      = "db-admin"
  })
}

# ==============================================================================
# KUBERNETES SECRETS — Sync DB credentials into cluster for app consumption
# ==============================================================================

resource "kubernetes_secret" "postgresql_app_creds" {
  for_each = var.postgresql_app_users

  metadata {
    # K8s names cannot contain underscores (RFC 1123).
    name      = "db-creds-postgresql-${replace(each.key, "_", "-")}"
    namespace = var.namespace
    labels = {
      app        = replace(each.key, "_", "-")
      db-type    = "postgresql"
      managed-by = "terraform"
    }
  }

  type = "Opaque"

  data = {
    DB_USERNAME     = each.key
    DB_PASSWORD     = each.value.password
    DB_NAME         = local.shared_mode ? var.shared_database : (each.value.database != "" ? each.value.database : each.key)
    DB_HOST         = var.db_host
    DB_PORT         = "5432"
    DB_SCHEMA       = length(try(each.value.schemas, [])) > 0 ? each.value.schemas[0] : each.key
    DATABASE_URL    = "postgresql://${each.key}:${each.value.password}@${var.db_host}:5432/${local.shared_mode ? var.shared_database : (each.value.database != "" ? each.value.database : each.key)}"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [data]
  }
}

resource "kubernetes_secret" "mongodb_app_creds" {
  for_each = var.mongodb_app_users

  metadata {
    name      = "db-creds-mongodb-${replace(each.key, "_", "-")}"
    namespace = var.namespace
    labels = {
      app        = replace(each.key, "_", "-")
      db-type    = "mongodb"
      managed-by = "terraform"
    }
  }

  type = "Opaque"

  data = {
    DB_USERNAME = each.key
    DB_PASSWORD = each.value.password
    DB_NAME     = local.shared_mode && each.value.database == "" ? var.shared_database : (each.value.database != "" ? each.value.database : each.key)
    DB_HOST     = var.mongo_host
    DB_PORT     = "27017"
    MONGO_URL   = "mongodb://${each.key}:${each.value.password}@${var.mongo_host}:27017/${local.shared_mode && each.value.database == "" ? var.shared_database : (each.value.database != "" ? each.value.database : each.key)}"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [data]
  }
}
