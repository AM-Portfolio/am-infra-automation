output "environment" {
  value = var.environment
}

output "postgresql" {
  value = local.row.postgresql
}

output "mongodb" {
  value = local.row.mongodb
}

output "redis" {
  value = local.row.redis
}

output "kafka" {
  value = local.row.kafka
}

output "influxdb" {
  value = local.row.influxdb
}

output "minio" {
  value = local.row.minio
}

output "vault" {
  value = local.row.vault
}
