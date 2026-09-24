output "infra_paths" {
  value = [
    "${var.vault_mount}/data/${var.env}/infra/postgres",
    "${var.vault_mount}/data/${var.env}/infra/mongodb",
    "${var.vault_mount}/data/${var.env}/infra/redis",
    "${var.vault_mount}/data/${var.env}/infra/kafka",
    "${var.vault_mount}/data/${var.env}/infra/influxdb",
    "${var.vault_mount}/data/${var.env}/infra/observability",
  ]
}

output "service_names" {
  value = sort(keys(local.services_data))
}

output "service_paths" {
  value = [for s in sort(keys(local.services_data)) : "${var.vault_mount}/data/${var.env}/services/${s}"]
}
