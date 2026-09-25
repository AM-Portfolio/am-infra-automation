resource "random_password" "postgres" {
  length  = 24
  special = false
}

resource "random_password" "mongo" {
  length  = 24
  special = false
}

resource "random_password" "redis" {
  length  = 24
  special = false
}

resource "random_password" "minio" {
  length  = 24
  special = false
}

resource "random_password" "influx" {
  length  = 32
  special = false
}

resource "random_password" "app_users" {
  for_each = toset([
    "keycloak", "temporal", "lago", "n8n", "openproject", "litellm", "langfuse", "growthbook"
  ])
  length  = 24
  special = false
}

resource "local_sensitive_file" "store_creds" {
  filename = "/data/am-state/credentials/prod-infra-stores.env"
  content  = <<-EOT
    # VPS1 am-prod-infra store creds. Not for git. Shared DB platform + per-module users.
    POSTGRES_USER=postgres
    POSTGRES_PASSWORD=${random_password.postgres.result}
    POSTGRES_DB=postgres
    PLATFORM_PG_DATABASE=platform
    PLATFORM_MONGO_DATABASE=platform
    MONGO_USER=admin
    MONGO_PASSWORD=${random_password.mongo.result}
    REDIS_PASSWORD=${random_password.redis.result}
    MINIO_ROOT_USER=amminio
    MINIO_ROOT_PASSWORD=${random_password.minio.result}
    INFLUX_USER=admin
    INFLUX_PASSWORD=${random_password.influx.result}
    INFLUX_ORG=asrax
    INFLUX_BUCKET=am
    INFLUX_TOKEN=${random_password.influx.result}
    PG_USER_KEYCLOAK=${random_password.app_users["keycloak"].result}
    PG_USER_TEMPORAL=${random_password.app_users["temporal"].result}
    PG_USER_LAGO=${random_password.app_users["lago"].result}
    PG_USER_N8N=${random_password.app_users["n8n"].result}
    PG_USER_OPENPROJECT=${random_password.app_users["openproject"].result}
    PG_USER_LITELLM=${random_password.app_users["litellm"].result}
    PG_USER_LANGFUSE=${random_password.app_users["langfuse"].result}
    PG_USER_AM_SUBSCRIPTION=${random_password.postgres.result}
    PG_USER_AM_USER_PLATFORM=${random_password.postgres.result}
    MONGO_USER_GROWTHBOOK=${random_password.app_users["growthbook"].result}
    REDIS_USER_LANGFUSE=${random_password.app_users["langfuse"].result}
    MINIO_USER_LANGFUSE=${random_password.app_users["langfuse"].result}
  EOT
}
