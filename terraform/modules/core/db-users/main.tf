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

# Create a dedicated DB user per application that needs PostgreSQL access
resource "postgresql_role" "app_users" {
  for_each = var.postgresql_app_users

  name     = each.key
  login    = true
  password = each.value.password

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [password] # Managed via Vault rotation
  }
}

resource "postgresql_database" "app_databases" {
  for_each = var.postgresql_app_users

  name  = each.value.database != "" ? each.value.database : each.key
  owner = postgresql_role.app_users[each.key].name

  lifecycle {
    prevent_destroy = true
  }
}

resource "postgresql_grant" "app_user_grants" {
  for_each = var.postgresql_app_users

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
  for_each = var.postgresql_app_users

  mount               = "secret"
  name                = "infra/db-users/postgresql/${each.key}"
  delete_all_versions = false

  data_json = jsonencode({
    username     = each.key
    password     = each.value.password
    database     = each.value.database != "" ? each.value.database : each.key
    host         = "postgresql.infra.svc.cluster.local"
    port         = "5432"
    database_url = "postgresql+asyncpg://${each.key}:${each.value.password}@postgresql.infra.svc.cluster.local:5432/${each.value.database != "" ? each.value.database : each.key}"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "vault_kv_secret_v2" "mongodb_creds" {
  for_each = var.mongodb_app_users

  mount               = "secret"
  name                = "infra/db-users/mongodb/${each.key}"
  delete_all_versions = false

  data_json = jsonencode({
    username     = each.key
    password     = each.value.password
    database     = each.value.database != "" ? each.value.database : each.key
    host         = "mongodb.infra.svc.cluster.local"
    port         = "27017"
    mongo_url    = "mongodb://${each.key}:${each.value.password}@mongodb.infra.svc.cluster.local:27017/${each.value.database != "" ? each.value.database : each.key}"
  })

  lifecycle {
    prevent_destroy = true
  }
}

# ==============================================================================
# VAULT POLICIES — Per-App read access to their own DB credentials
# ==============================================================================

resource "vault_policy" "app_db_policies" {
  for_each = merge(
    { for k, v in var.postgresql_app_users : "pg-${k}" => "infra/data/db-users/postgresql/${k}" },
    { for k, v in var.mongodb_app_users    : "mg-${k}" => "infra/data/db-users/mongodb/${k}" }
  )

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
  for_each = var.db_admin_accounts

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
    name      = "db-creds-postgresql-${each.key}"
    namespace = var.namespace
    labels = {
      app        = each.key
      db-type    = "postgresql"
      managed-by = "terraform"
    }
  }

  type = "Opaque"

  data = {
    DB_USERNAME     = each.key
    DB_PASSWORD     = each.value.password
    DB_NAME         = each.value.database != "" ? each.value.database : each.key
    DB_HOST         = "postgresql.infra.svc.cluster.local"
    DB_PORT         = "5432"
    DATABASE_URL    = "postgresql+asyncpg://${each.key}:${each.value.password}@postgresql.infra.svc.cluster.local:5432/${each.value.database != "" ? each.value.database : each.key}"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [data]
  }
}

resource "kubernetes_secret" "mongodb_app_creds" {
  for_each = var.mongodb_app_users

  metadata {
    name      = "db-creds-mongodb-${each.key}"
    namespace = var.namespace
    labels = {
      app        = each.key
      db-type    = "mongodb"
      managed-by = "terraform"
    }
  }

  type = "Opaque"

  data = {
    DB_USERNAME = each.key
    DB_PASSWORD = each.value.password
    DB_NAME     = each.value.database != "" ? each.value.database : each.key
    DB_HOST     = "mongodb.infra.svc.cluster.local"
    DB_PORT     = "27017"
    MONGO_URL   = "mongodb://${each.key}:${each.value.password}@mongodb.infra.svc.cluster.local:27017/${each.value.database != "" ? each.value.database : each.key}"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [data]
  }
}
