# Sizing stub only. Full store modules are copied from kind-fleet/dev/stores on first VPS create.
# Do not terraform apply this folder on the laptop.
#
# When copying from dev/stores, KEEP these Vault flags (required on every VPS):
#   enable_watcher  = true
#   enable_unsealer = false
# Also seed Secret vault-unseal-keys from that host's vault-prod-infra.json.
# Apply kind-fleet/prod/exposer (Docker DNS am-prod-infra-control-plane) — never bake Kind IP.

locals {
  env = "prod"
}

resource "terraform_data" "env_folder_guard" {
  input = local.env
  lifecycle {
    precondition {
      condition     = local.env == "prod"
      error_message = "kind-fleet/prod/stores must set local.env = \"prod\". Do not apply prod sizes on the laptop."
    }
  }
}

module "sizing" {
  source      = "../../../modules/core/store-sizing"
  environment = local.env
}

output "environment" { value = module.sizing.environment }
output "postgresql" { value = module.sizing.postgresql }
output "mongodb" { value = module.sizing.mongodb }
output "redis" { value = module.sizing.redis }
output "kafka" { value = module.sizing.kafka }
output "influxdb" { value = module.sizing.influxdb }
output "minio" { value = module.sizing.minio }
output "vault" { value = module.sizing.vault }
