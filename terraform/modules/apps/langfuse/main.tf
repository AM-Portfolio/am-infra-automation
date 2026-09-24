# Langfuse web + in-module ClickHouse. Reuse fleet Redis + MinIO.
# Attach: PG platform / user langfuse.

locals {
  domain_suffix = var.environment == "prod" ? "" : "-${var.environment}"
  ui_host       = "langfuse${local.domain_suffix}.${var.root_domain}"
  # Prisma uses ?schema=; search_path alone is ignored and races on _prisma_migrations.
  database_url = "postgresql://${var.db_user}:${urlencode(var.db_password)}@${var.db_host}:5432/${var.db_name}?schema=${var.db_schema}&sslmode=disable"
  redis_url     = "redis://:${urlencode(var.redis_password)}@${var.redis_host}:6379/${var.redis_db}"
}

resource "random_id" "ch" {
  byte_length = 16
}

resource "random_password" "salt" {
  length  = 32
  special = false
}

resource "kubernetes_secret" "langfuse" {
  metadata {
    name      = "langfuse-secrets"
    namespace = var.namespace
  }
  data = {
    DATABASE_URL            = local.database_url
    REDIS_CONNECTION_STRING = local.redis_url
    CLICKHOUSE_PASSWORD     = random_id.ch.hex
    NEXTAUTH_SECRET         = random_password.salt.result
    SALT                    = random_password.salt.result
  }
}

resource "kubernetes_stateful_set" "clickhouse" {
  metadata {
    name      = "langfuse-clickhouse"
    namespace = var.namespace
    labels    = { app = "langfuse-clickhouse" }
  }
  spec {
    service_name = "langfuse-clickhouse"
    replicas     = 1
    selector { match_labels = { app = "langfuse-clickhouse" } }
    template {
      metadata { labels = { app = "langfuse-clickhouse" } }
      spec {
        container {
          name  = "clickhouse"
          image = var.clickhouse_image
          port { container_port = 8123 }
          resources {
            requests = {
              cpu    = var.clickhouse_cpu_request
              memory = var.clickhouse_memory_request
            }
            limits = {
              cpu    = var.clickhouse_cpu_limit
              memory = var.clickhouse_memory_limit
            }
          }
          env {
            name  = "CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT"
            value = "1"
          }
          env {
            name  = "CLICKHOUSE_PASSWORD"
            value = random_id.ch.hex
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "clickhouse" {
  metadata {
    name      = "langfuse-clickhouse"
    namespace = var.namespace
  }
  spec {
    selector = { app = "langfuse-clickhouse" }
    port {
      port        = 8123
      target_port = 8123
    }
  }
}

resource "helm_release" "langfuse" {
  name             = "langfuse"
  repository       = "https://langfuse.github.io/langfuse-k8s"
  chart            = "langfuse"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = false
  wait             = true
  timeout          = 900

  values = [yamlencode({
    postgresql = { deploy = false }
    redis      = { deploy = false }
    clickhouse = { deploy = false }
    s3 = {
      deploy         = false
      bucket         = var.minio_bucket
      region         = "auto"
      endpoint       = "http://${var.minio_endpoint}"
      forcePathStyle = true
      accessKeyId    = { value = var.minio_user }
      secretAccessKey = { value = var.minio_password }
      eventUpload = {
        bucket         = var.minio_bucket
        endpoint       = "http://${var.minio_endpoint}"
        forcePathStyle = true
      }
      mediaUpload = {
        enabled        = true
        bucket         = var.minio_bucket
        endpoint       = "http://${var.minio_endpoint}"
        forcePathStyle = true
      }
      batchExport = {
        bucket         = var.minio_bucket
        endpoint       = "http://${var.minio_endpoint}"
        forcePathStyle = true
      }
    }
    langfuse = {
      salt = { secretKeyRef = { name = kubernetes_secret.langfuse.metadata[0].name, key = "SALT" } }
      nextauth = {
        url    = "https://${local.ui_host}"
        secret = { secretKeyRef = { name = kubernetes_secret.langfuse.metadata[0].name, key = "NEXTAUTH_SECRET" } }
      }
      resources = {
        requests = { cpu = var.web_cpu_request, memory = var.web_memory_request }
        limits   = { cpu = var.web_cpu_limit, memory = var.web_memory_limit }
      }
      additionalEnv = [
        { name = "DATABASE_URL", valueFrom = { secretKeyRef = { name = kubernetes_secret.langfuse.metadata[0].name, key = "DATABASE_URL" } } },
        { name = "REDIS_CONNECTION_STRING", valueFrom = { secretKeyRef = { name = kubernetes_secret.langfuse.metadata[0].name, key = "REDIS_CONNECTION_STRING" } } },
        { name = "CLICKHOUSE_URL", value = "http://langfuse-clickhouse:8123" },
        { name = "CLICKHOUSE_USER", value = "default" },
        { name = "CLICKHOUSE_PASSWORD", valueFrom = { secretKeyRef = { name = kubernetes_secret.langfuse.metadata[0].name, key = "CLICKHOUSE_PASSWORD" } } },
        # Single-node ClickHouse has no ZooKeeper — ON CLUSTER migrations fail. Apply CH DDL out-of-band if needed.
        { name = "LANGFUSE_AUTO_POSTGRES_MIGRATION_DISABLED", value = "true" },
        { name = "LANGFUSE_AUTO_CLICKHOUSE_MIGRATION_DISABLED", value = "true" },
      ]
    }
    # Chart top-level replica knobs (not nested under langfuse).
    web    = { replicaCount = 1 }
    worker = { replicaCount = 1 }
  })]

  depends_on = [kubernetes_stateful_set.clickhouse, kubernetes_service.clickhouse]
}

output "ui_host" { value = local.ui_host }
