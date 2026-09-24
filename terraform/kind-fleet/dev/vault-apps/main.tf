# Seeds Vault apps/data/dev/* for Kind-fleet AM apps (infra + all catalog services).
# Separate from kind-fleet/dev/apps so cluster destroy does not wipe Vault.
#
#   cd terraform/kind-fleet
#   .\init-backend.ps1 -Env dev -Role vault-apps
#   terraform -chdir=dev/vault-apps init -backend-config=backend.hcl
#   terraform -chdir=dev/vault-apps apply
#
# Or: ..\dev\apps\scripts\seed-vault-dev-apps.ps1

locals {
  env    = "dev"
  domain = "asrax.in"

  vault_keys_file = pathexpand("~/.asrax/vault-dev-infra.json")
  stores_env_file = pathexpand("~/.asrax/credentials.d/dev-infra-stores.env")
  kc_env_file     = pathexpand("~/.asrax/credentials.d/keycloak-kind-fleet-dev.env")

  vault_addr  = "https://vault-dev.asrax.in"
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
      condition     = local.env == "dev"
      error_message = "kind-fleet/dev/vault-apps must set local.env = \"dev\"."
    }
  }
}

module "seed" {
  source = "../../../modules/core/apps-vault-seed"

  env               = local.env
  domain            = local.domain
  postgres_user     = local.stores["POSTGRES_USER"]
  postgres_password = local.stores["POSTGRES_PASSWORD"]
  postgres_db       = try(local.stores["POSTGRES_DB"], "postgres")
  mongo_user        = local.stores["MONGO_USER"]
  mongo_password    = local.stores["MONGO_PASSWORD"]
  redis_password    = local.stores["REDIS_PASSWORD"]
  influx_token      = local.stores["INFLUX_TOKEN"]
  influx_org        = local.stores["INFLUX_ORG"]
  influx_bucket     = local.stores["INFLUX_BUCKET"]
  influx_password   = try(local.stores["INFLUX_PASSWORD"], "")
  keycloak_realm    = try(local.kc["KEYCLOAK_REALM"], "am-realm")
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
