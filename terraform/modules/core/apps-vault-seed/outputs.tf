output "infra_paths" {
  value = [
    "${var.vault_mount}/data/${var.env}/infra/postgres",
    "${var.vault_mount}/data/${var.env}/infra/mongodb",
    "${var.vault_mount}/data/${var.env}/infra/redis",
    "${var.vault_mount}/data/${var.env}/infra/kafka",
    "${var.vault_mount}/data/${var.env}/infra/influxdb",
    "${var.vault_mount}/data/${var.env}/infra/observability",
    "${var.vault_mount}/data/${var.env}/infra/shared-api",
  ]
}

output "service_names" {
  value = sort(keys(local.services_data))
}

output "service_paths" {
  value = [for s in sort(keys(local.services_data)) : "${var.vault_mount}/data/${var.env}/services/${s}"]
}

output "identity_keycloak_admin_user" {
  value = try(local.services_data["am-identity"]["KEYCLOAK_ADMIN_USER"], "")
}

output "identity_oidc_issuer" {
  value = try(local.services_data["am-identity"]["OIDC_ISSUER"], "")
}
