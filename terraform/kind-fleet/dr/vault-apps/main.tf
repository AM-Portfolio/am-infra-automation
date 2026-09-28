# Seeds Vault apps/data/dr/* for Kind-fleet AM apps (infra + all catalog services).
# Separate from kind-fleet/dr/apps so cluster destroy does not wipe Vault.
#
#   On VPS3:
#   cd /home/am-ops/src/am-infra-automation/terraform/kind-fleet
#   ./init-backend.ps1 -Env dr -Role vault-apps
#   terraform -chdir=dr/vault-apps init -backend-config=backend.hcl
#   terraform -chdir=dr/vault-apps apply
#
# Requires platform-written /data/am-state/credentials/dr/keycloak-admin.env
# (compat symlink: dr-keycloak-admin.env). Hosts auto-rewrite via apps-vault-seed.

locals {
  env    = "dr"
  domain = "asrax.in"

  vault_keys_file = "/data/am-state/vault-dr-infra.json"
  stores_env_file = (
    fileexists("/data/am-state/credentials/dr/infra-stores.env")
    ? "/data/am-state/credentials/dr/infra-stores.env"
    : "/data/am-state/credentials/dr-infra-stores.env"
  )
  kc_env_file = (
    fileexists("/data/am-state/credentials/dr/keycloak-admin.env")
    ? "/data/am-state/credentials/dr/keycloak-admin.env"
    : "/data/am-state/credentials/dr-keycloak-admin.env"
  )

  vault_addr  = "https://vault-dr.${local.domain}"
  vault_token = jsondecode(replace(file(local.vault_keys_file), "\ufeff", "")).root_token

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
      condition     = local.env == "dr"
      error_message = "kind-fleet/dr/vault-apps must set local.env = \"dr\"."
    }
  }
}

resource "terraform_data" "require_kc_admin_env" {
  input = local.kc_env_file
  lifecycle {
    precondition {
      condition     = fileexists(local.kc_env_file) && length(try(local.kc["KEYCLOAK_ADMIN_PASSWORD"], "")) >= 8
      error_message = "Missing ${local.kc_env_file} with KEYCLOAK_ADMIN_PASSWORD — re-apply kind-fleet/dr/platform (writes credentials/dr/keycloak-admin.env)."
    }
  }
}

module "seed" {
  source = "../../../modules/core/apps-vault-seed"

  env                     = local.env
  domain                  = local.domain
  postgres_user           = local.stores["POSTGRES_USER"]
  postgres_password       = local.stores["POSTGRES_PASSWORD"]
  postgres_db             = try(local.stores["POSTGRES_DB"], "postgres")
  mongo_user              = local.stores["MONGO_USER"]
  mongo_password          = local.stores["MONGO_PASSWORD"]
  redis_password          = local.stores["REDIS_PASSWORD"]
  influx_token            = local.stores["INFLUX_TOKEN"]
  influx_org              = local.stores["INFLUX_ORG"]
  influx_bucket           = local.stores["INFLUX_BUCKET"]
  influx_password         = try(local.stores["INFLUX_PASSWORD"], "")
  keycloak_realm          = try(local.kc["KEYCLOAK_REALM"], "am-realm")
  keycloak_admin_user     = try(local.kc["KEYCLOAK_ADMIN_USER"], "admin")
  keycloak_admin_password = local.kc["KEYCLOAK_ADMIN_PASSWORD"]

  depends_on = [terraform_data.require_kc_admin_env]
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
