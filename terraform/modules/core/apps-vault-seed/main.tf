resource "vault_kv_secret_v2" "infra_postgres" {
  mount               = var.vault_mount
  name                = "${var.env}/infra/postgres"
  delete_all_versions = false
  data_json           = jsonencode(local.infra_postgres)
}

resource "terraform_data" "require_keycloak_admin" {
  input = var.keycloak_admin_password
  lifecycle {
    precondition {
      condition     = length(var.keycloak_admin_password) >= 8 && !local.identity_admin_is_placeholder
      error_message = "apps-vault-seed requires keycloak_admin_password from platform Keycloak (refuse empty or *-fleet-keycloak-admin-password placeholders)."
    }
  }
}

resource "vault_kv_secret_v2" "infra_mongodb" {
  mount               = var.vault_mount
  name                = "${var.env}/infra/mongodb"
  delete_all_versions = false
  data_json           = jsonencode(local.infra_mongodb)
}

resource "vault_kv_secret_v2" "infra_redis" {
  mount               = var.vault_mount
  name                = "${var.env}/infra/redis"
  delete_all_versions = false
  data_json           = jsonencode(local.infra_redis)
}

resource "vault_kv_secret_v2" "infra_kafka" {
  mount               = var.vault_mount
  name                = "${var.env}/infra/kafka"
  delete_all_versions = false
  data_json           = jsonencode(local.infra_kafka)
}

resource "vault_kv_secret_v2" "infra_influxdb" {
  mount               = var.vault_mount
  name                = "${var.env}/infra/influxdb"
  delete_all_versions = false
  data_json           = jsonencode(local.infra_influxdb)
}

resource "vault_kv_secret_v2" "infra_observability" {
  mount               = var.vault_mount
  name                = "${var.env}/infra/observability"
  delete_all_versions = false
  data_json           = jsonencode(local.infra_observability)
}

resource "vault_kv_secret_v2" "infra_shared_api" {
  mount               = var.vault_mount
  name                = "${var.env}/infra/shared-api"
  delete_all_versions = false
  data_json           = jsonencode(local.infra_shared_api)
}

resource "vault_kv_secret_v2" "services" {
  for_each = local.services_data

  mount               = var.vault_mount
  name                = "${var.env}/services/${each.key}"
  delete_all_versions = false
  data_json           = jsonencode(each.value)

  depends_on = [terraform_data.require_keycloak_admin]
}

resource "vault_kv_secret_v2" "runtime_modules" {
  for_each = local.runtime_modules_data

  mount               = var.vault_mount
  name                = "${var.env}/runtime/modules/${each.key}"
  delete_all_versions = false
  data_json           = jsonencode(each.value)
}
