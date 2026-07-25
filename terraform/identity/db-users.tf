/*
resource "vault_mount" "secret" {
  path        = "secret"
  type        = "kv"
  options     = { version = "2" }
  description = "KV Version 2 secret engine for dynamic db credentials"
}
*/

module "db_users" {
  source                = "../modules/core/db-users"
  namespace             = var.namespace_infra
  infra_admins_group_id = module.authentik_core.infra_admins_group_id
  # depends_on            = [vault_mount.secret]

  postgresql_app_users = {
    "am-auth" = {
      password = var.am_auth_db_password
      database = "am_auth"
    }
    "am-market" = {
      password = var.am_market_db_password
      database = "am_market"
    }
  }

  mongodb_app_users = {
    "am-market" = {
      password = var.am_market_mongo_password
      database = "am_market"
      role     = "readWrite"
    }
  }

  db_admin_accounts = {
    "arvind-dba" = {
      display_name = "Arvind (DB Admin)"
      email        = "admin@${var.root_domain}"
      databases    = ["postgresql", "mongodb", "redis", "influxdb"]
    }
  }
}
