# Seeds Contabo Vault apps/data/dev/* (vault.asrax.in) via apps-vault-seed.
# Separate state from kind-fleet/dev/vault-apps (vault-dev).
#
# Contabo dig has NO separate dig Mongo/Redis/PG — store_hosts=contabo_prod
# (postgres|mongo|redis.asrax.in). Cluster admin creds come from Contabo
# apps/data/prod/infra/*; per-DB app users are dig-scoped (*_dev) with unique passwords.
#
# Track: docs/kind-fleet-clusters/contabo-vault-one/
#
#   cd terraform/kind-fleet
#   .\init-backend.ps1 -Env dev -Role vault-apps-contabo
#   terraform -chdir=dev/vault-apps-contabo init -backend-config=backend.hcl
#   terraform -chdir=dev/vault-apps-contabo plan
#   terraform -chdir=dev/vault-apps-contabo apply
#
# Requires:
#   ~/.asrax/vault-contabo-infra.json  { "root_token": "..." }
#   OR -var="vault_token=..." / TF_VAR_vault_token
#   ~/.asrax/credentials.d/dev-infra-stores.env
#   ~/.asrax/credentials.d/keycloak-kind-fleet-dev.env (or keycloak-kind-nonprod.env)
# Prefer Google/OIDC from preprod via terraform.tfvars extra_service_data (never commit secrets).

variable "vault_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Contabo Vault root/admin token if vault-contabo-infra.json is absent."
}

variable "extra_service_data" {
  type        = map(map(string))
  default     = {}
  sensitive   = true
  description = "Prefer preprod Google/OIDC overlays. Never commit real values — use local terraform.tfvars."
}

variable "keycloak_realm" {
  type    = string
  default = "am-dev-realm"
}

variable "ui_base_url" {
  type    = string
  default = "https://am-dev.asrax.in"
}

locals {
  env    = "dev"
  domain = "asrax.in"

  vault_keys_file = pathexpand("~/.asrax/vault-contabo-infra.json")
  stores_env_file = pathexpand("~/.asrax/credentials.d/dev-infra-stores.env")
  kc_env_file = (
    fileexists(pathexpand("~/.asrax/credentials.d/keycloak-kind-fleet-dev.env"))
    ? pathexpand("~/.asrax/credentials.d/keycloak-kind-fleet-dev.env")
    : pathexpand("~/.asrax/credentials.d/keycloak-kind-nonprod.env")
  )

  vault_addr = "https://vault.asrax.in"
  vault_token_from_file = (
    fileexists(local.vault_keys_file)
    ? try(jsondecode(replace(file(local.vault_keys_file), "\ufeff", "")).root_token, "")
    : ""
  )
  vault_token_resolved = (
    length(local.vault_token_from_file) >= 8
    ? local.vault_token_from_file
    : var.vault_token
  )

  stores_raw = replace(file(local.stores_env_file), "\ufeff", "")
  stores_lines = [
    for l in split("\n", local.stores_raw) :
    trimspace(replace(l, "\r", ""))
    if length(trimspace(replace(l, "\r", ""))) > 0 && !startswith(trimspace(replace(l, "\r", "")), "#")
  ]
  stores = {
    for l in local.stores_lines :
    trimspace(split("=", l)[0]) => trim(
      trimspace(join("=", slice(split("=", l), 1, length(split("=", l))))),
      "\"'"
    )
  }

  kc_raw = fileexists(local.kc_env_file) ? replace(file(local.kc_env_file), "\ufeff", "") : ""
  kc_lines = [
    for l in split("\n", local.kc_raw) :
    trimspace(replace(l, "\r", ""))
    if length(trimspace(replace(l, "\r", ""))) > 0 && !startswith(trimspace(replace(l, "\r", "")), "#")
  ]
  kc = {
    for l in local.kc_lines :
    trimspace(split("=", l)[0]) => trim(
      trimspace(join("=", slice(split("=", l), 1, length(split("=", l))))),
      "\"'"
    )
  }
}

resource "terraform_data" "env_folder_guard" {
  input = local.env
  lifecycle {
    precondition {
      condition     = local.env == "dev"
      error_message = "kind-fleet/dev/vault-apps-contabo must set local.env = \"dev\"."
    }
  }
}

resource "terraform_data" "require_contabo_token" {
  input = local.vault_token_resolved
  lifecycle {
    precondition {
      condition     = length(local.vault_token_resolved) >= 8
      error_message = "Missing Contabo Vault token: place ~/.asrax/vault-contabo-infra.json (root_token) or -var=vault_token=..."
    }
  }
}

resource "terraform_data" "require_kc_admin_env" {
  input = local.kc_env_file
  lifecycle {
    precondition {
      condition = length(coalesce(
        try(local.kc["KEYCLOAK_ADMIN_PASSWORD"], ""),
        try(local.kc["KC_ADMIN_PASSWORD"], ""),
        try(local.kc["KEYCLOAK_PASSWORD"], "")
      )) >= 8
      error_message = "Missing Keycloak admin password in ${local.kc_env_file}."
    }
  }
}

# Contabo dig shares Contabo prod stores (no mongodb-dev / redis-dev plane).
data "vault_kv_secret_v2" "contabo_prod_postgres" {
  mount = "apps"
  name  = "prod/infra/postgres"
}

data "vault_kv_secret_v2" "contabo_prod_mongodb" {
  mount = "apps"
  name  = "prod/infra/mongodb"
}

data "vault_kv_secret_v2" "contabo_prod_redis" {
  mount = "apps"
  name  = "prod/infra/redis"
}

locals {
  contabo_pg_user = coalesce(
    try(data.vault_kv_secret_v2.contabo_prod_postgres.data["POSTGRES_USER"], null),
    try(data.vault_kv_secret_v2.contabo_prod_postgres.data["username"], null),
    "postgres"
  )
  contabo_pg_password = coalesce(
    try(data.vault_kv_secret_v2.contabo_prod_postgres.data["POSTGRES_PASSWORD"], null),
    try(data.vault_kv_secret_v2.contabo_prod_postgres.data["password"], null),
    ""
  )
  contabo_mongo_user = coalesce(
    try(data.vault_kv_secret_v2.contabo_prod_mongodb.data["username"], null),
    "admin"
  )
  contabo_mongo_password = try(data.vault_kv_secret_v2.contabo_prod_mongodb.data["password"], "")
  contabo_redis_password = try(data.vault_kv_secret_v2.contabo_prod_redis.data["password"], "")
}

resource "terraform_data" "require_contabo_prod_store_creds" {
  input = "${length(local.contabo_pg_password)}:${length(local.contabo_mongo_password)}:${length(local.contabo_redis_password)}"
  lifecycle {
    precondition {
      condition = (
        length(local.contabo_pg_password) >= 8 &&
        length(local.contabo_mongo_password) >= 8 &&
        length(local.contabo_redis_password) >= 8
      )
      error_message = "Contabo dig seed needs Contabo prod store passwords from apps/data/prod/infra/{postgres,mongodb,redis}."
    }
  }
}

module "seed" {
  source = "../../../modules/core/apps-vault-seed"

  env                     = local.env
  domain                  = local.domain
  store_hosts             = "contabo_prod"
  postgres_user           = local.contabo_pg_user
  postgres_password       = local.contabo_pg_password
  postgres_db             = try(local.stores["POSTGRES_DB"], "postgres")
  mongo_user              = local.contabo_mongo_user
  mongo_password          = local.contabo_mongo_password
  redis_password          = local.contabo_redis_password
  influx_token            = local.stores["INFLUX_TOKEN"]
  influx_org              = local.stores["INFLUX_ORG"]
  influx_bucket           = local.stores["INFLUX_BUCKET"]
  influx_password         = try(local.stores["INFLUX_PASSWORD"], "")
  keycloak_realm          = var.keycloak_realm
  keycloak_admin_user     = try(local.kc["KEYCLOAK_ADMIN_USER"], try(local.kc["KC_ADMIN_USER"], "admin"))
  keycloak_admin_password = coalesce(
    try(local.kc["KEYCLOAK_ADMIN_PASSWORD"], ""),
    try(local.kc["KC_ADMIN_PASSWORD"], ""),
    try(local.kc["KEYCLOAK_PASSWORD"], "")
  )
  ui_base_url        = var.ui_base_url
  extra_service_data = var.extra_service_data

  depends_on = [
    terraform_data.require_kc_admin_env,
    terraform_data.require_contabo_token,
    terraform_data.require_contabo_prod_store_creds,
  ]
}

output "vault_addr" {
  value = local.vault_addr
}

output "infra_paths" {
  value = module.seed.infra_paths
}

output "service_names" {
  value = module.seed.service_names
}

output "service_count" {
  value = length(module.seed.service_names)
}
