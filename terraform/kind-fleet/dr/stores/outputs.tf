output "namespaces" {
  value = {
    infra = module.namespaces.infra_ns
    vault = module.namespaces.vault_ns
  }
}

output "shared_databases" {
  value = {
    postgres = "platform"
    mongo    = "platform"
  }
}

output "app_users" {
  value = {
    postgres = ["keycloak", "temporal", "lago", "n8n", "openproject", "litellm", "langfuse"]
    mongo    = ["growthbook"]
    redis    = ["langfuse"]
    minio    = ["langfuse"]
  }
}

output "cluster_services" {
  value = {
    postgres = "postgres-dr.asrax.in:5432"
    mongo    = "mongodb-dr.asrax.in:27017"
    redis    = "redis-dr.asrax.in:6379"
    kafka    = "kafka-dr.asrax.in:9092"
    influx   = "influxdb-dr.asrax.in:8086"
    minio    = "minio-dr.asrax.in:9000"
    vault    = "https://vault-dr.asrax.in"
  }
}

output "creds_file" {
  value = "/data/am-state/credentials/dr/infra-stores.env"
}

output "environment" {
  value = module.sizing.environment
}

output "note" {
  value = "Platform Helm (temporal/lago/n8n/…) is Phase 3 — not this stack. Access still off. Vault seed is Phase 4."
}
