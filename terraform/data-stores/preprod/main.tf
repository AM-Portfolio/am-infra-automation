# ==============================================================================
# LOCAL ENVIRONMENT: DATA STORES ENTRYPOINT
# ==============================================================================

terraform {
  backend "local" {}
}

data "terraform_remote_state" "foundation" {
  backend = "local"
  config = {
    path = "/data/am-state/foundation.tfstate"
  }
}

locals {
  creds = data.terraform_remote_state.foundation.outputs.credentials
}

# ── 2. Read Secrets from Vault ───────────────────────────────────────────────
data "vault_kv_secret_v2" "databases" {
  mount = "secret"
  name  = "${var.environment}/infra/databases"
}

locals {
  vault_creds = data.vault_kv_secret_v2.databases.data
}

module "data_stores" {
  source = "./.."

  root_domain             = var.root_domain
  namespace_infra         = data.terraform_remote_state.foundation.outputs.infra_ns
  namespace_vault         = data.terraform_remote_state.foundation.outputs.vault_ns
  environment             = var.environment
  vault_root_token        = var.vault_root_token
  
  mongodb_password        = var.mongodb_password    != "" ? var.mongodb_password    : local.creds.mongodb_root
  postgresql_password     = var.postgresql_password != "" ? var.postgresql_password : local.creds.postgres_root
  pgadmin_password        = var.pgadmin_password    != "" ? var.pgadmin_password    : "admin123"
  redis_password          = var.redis_password      != "" ? var.redis_password      : local.creds.redis_password
  influxdb_password       = var.influxdb_password   != "" ? var.influxdb_password   : local.creds.influx_token
  influxdb_token          = var.influxdb_token      != "" ? var.influxdb_token      : local.creds.influx_token
  
  minio_root_user         = var.minio_root_user != "" ? var.minio_root_user : local.vault_creds.minio_root_user
  minio_root_password     = var.minio_root_password != "" ? var.minio_root_password : local.vault_creds.minio_root_password
}
