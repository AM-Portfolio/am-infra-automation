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
    postgres = "postgres-dev.asrax.in:5432"
    mongo    = "mongo-dev.asrax.in:27017"
    redis    = "redis-dev.asrax.in:6379"
    kafka    = "kafka-dev.asrax.in:9092"
    influx   = "influx-dev.asrax.in:8086"
    minio    = "minio-dev.asrax.in:9000"
    vault    = "https://vault-dev.asrax.in"
  }
}

output "creds_file" {
  value = pathexpand("~/.asrax/credentials.d/dev-infra-stores.env")
}

output "note" {
  value = "Platform Helm (temporal/lago/n8n/growthbook/openproject/litellm/langfuse) is not applied on this stack."
}
