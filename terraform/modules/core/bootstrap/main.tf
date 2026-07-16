# ==============================================================================
# Bootstrap Module — The "Seed" of Infrastructure
# ==============================================================================
# Generates random passwords and keys for all core services.
# These values are passed to other modules and eventually persisted in Vault.
# ==============================================================================

# 1. GENERATE PASSWORDS
resource "random_password" "postgres_vault" {
  length  = 20
  special = false
}

resource "random_password" "authentik_bootstrap" {
  length  = 24
  special = false
}

resource "random_password" "authentik_pg_pass" {
  length  = 20
  special = false
}

resource "random_password" "db_pg_root" {
  length  = 20
  special = false
}

resource "random_password" "db_mongo_root" {
  length  = 20
  special = false
}

resource "random_password" "db_redis_pass" {
  length  = 16
  special = false
}

resource "random_password" "influx_admin_token" {
  length  = 32
  special = false
}

# 2. OUTPUTS
output "credentials" {
  description = "A map of all automatically generated seed credentials"
  sensitive   = true
  value = {
    vault_unseal_key    = random_password.postgres_vault.result # Temporary unseal seed
    authentik_bootstrap = random_password.authentik_bootstrap.result
    authentik_postgres  = random_password.authentik_pg_pass.result
    postgres_root       = random_password.db_pg_root.result
    mongodb_root        = random_password.db_mongo_root.result
    redis_password      = random_password.db_redis_pass.result
    influx_token        = random_password.influx_admin_token.result
  }
}
