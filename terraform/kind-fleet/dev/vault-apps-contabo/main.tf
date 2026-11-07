# Seeds Contabo Vault apps/data/dev/* (vault.asrax.in) via apps-vault-seed.
# IAM-4: does NOT copy Contabo prod admin passwords.
# Dig principals use DIG_PRINCIPAL_SEED → dig_vault_seed + sha256-derived *_dev users.
# Hosts remain Contabo prod FQDNs (store_hosts=contabo_prod) — dig has no separate store plane.
#
# Requires:
#   ~/.asrax/vault-contabo-infra.json
#   ~/.asrax/credentials.d/dig-principal-seed.env   DIG_PRINCIPAL_SEED=...
#   ~/.asrax/credentials.d/keycloak-kind-fleet-dev.env (or keycloak-kind-nonprod.env)
# Optional: ~/.asrax/credentials.d/dev-infra-stores.env for Influx only

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
  type        = string
  default     = "am-dev-realm"
  description = "Realm on Contabo prod Keycloak (auth.asrax.in). No dig Keycloak pods."
}

variable "ui_base_url" {
  type    = string
  default = "https://am-dev.asrax.in"
}

variable "dig_principal_seed" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Override DIG_PRINCIPAL_SEED; else read dig-principal-seed.env."
}

locals {
  env    = "dev"
  domain = "asrax.in"

  vault_keys_file = pathexpand("~/.asrax/vault-contabo-infra.json")
  seed_env_file   = pathexpand("~/.asrax/credentials.d/dig-principal-seed.env")
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

  seed_raw = fileexists(local.seed_env_file) ? replace(file(local.seed_env_file), "\ufeff", "") : ""
  seed_lines = [
    for l in split("\n", local.seed_raw) :
    trimspace(replace(l, "\r", ""))
    if length(trimspace(replace(l, "\r", ""))) > 0 && !startswith(trimspace(replace(l, "\r", "")), "#")
  ]
  seed_map = {
    for l in local.seed_lines :
    trimspace(split("=", l)[0]) => trim(
      trimspace(join("=", slice(split("=", l), 1, length(split("=", l))))),
      "\"'"
    )
  }
  dig_seed = coalesce(
    length(var.dig_principal_seed) >= 16 ? var.dig_principal_seed : null,
    try(local.seed_map["DIG_PRINCIPAL_SEED"], ""),
    ""
  )

  stores_raw = fileexists(local.stores_env_file) ? replace(file(local.stores_env_file), "\ufeff", "") : ""
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
      error_message = "Missing Contabo Vault token: ~/.asrax/vault-contabo-infra.json or -var=vault_token=..."
    }
  }
}

resource "terraform_data" "require_dig_seed" {
  input = local.dig_seed
  lifecycle {
    precondition {
      condition     = length(local.dig_seed) >= 16
      error_message = "IAM-4: set DIG_PRINCIPAL_SEED in ~/.asrax/credentials.d/dig-principal-seed.env (run provision-dig-contabo-users.ps1 first)."
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

# Dig Vault uses dig_vault_seed (+ derived *_dev passwords inside apps-vault-seed).
# Never pull Contabo prod admin from apps/data/prod/infra/*.
module "seed" {
  source = "../../../modules/core/apps-vault-seed"

  env                     = local.env
  domain                  = local.domain
  store_hosts             = "contabo_prod"
  postgres_user           = "dig_vault_seed"
  postgres_password       = local.dig_seed
  postgres_db             = try(local.stores["POSTGRES_DB"], "postgres")
  mongo_user              = "dig_vault_seed"
  mongo_password          = local.dig_seed
  redis_password          = local.dig_seed
  influx_token            = try(local.stores["INFLUX_TOKEN"], "${local.env}-fleet-influx-token")
  influx_org              = try(local.stores["INFLUX_ORG"], "influxdata")
  # Contabo dig → am_dev bucket (bidirectional isolation from prod bucket am)
  influx_bucket           = try(local.stores["INFLUX_BUCKET_DEV"], try(local.stores["INFLUX_BUCKET"], "am_dev"))
  influx_password         = try(local.stores["INFLUX_PASSWORD"], local.dig_seed)
  keycloak_realm          = var.keycloak_realm
  keycloak_public_host    = "auth.asrax.in"
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
    terraform_data.require_dig_seed,
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

output "iam4_note" {
  value = "Dig Vault uses dig_vault_seed + DIG_PRINCIPAL_SEED; Contabo prod admin no longer copied."
}
