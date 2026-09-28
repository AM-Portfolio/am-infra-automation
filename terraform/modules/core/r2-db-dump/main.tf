# TF-managed critical DB dump → R2 (asrax-disaster).
# When enabled: builds local image, loads into Kind, CronJob every 6h.

variable "enabled" {
  type    = bool
  default = false
}

variable "namespace" {
  type    = string
  default = "infra"
}

variable "schedule" {
  type    = string
  default = "0 */6 * * *"
}

variable "r2_bucket" {
  type    = string
  default = "asrax-disaster"
}

variable "prefix" {
  type    = string
  default = "prod"
}

variable "service_account_name" {
  type    = string
  default = "am-r2-db-dump"
}

variable "image" {
  type        = string
  default     = "am-r2-db-dump:local"
  description = "Image loaded into Kind (built by null_resource when enabled)."
}

variable "kind_cluster_name" {
  type    = string
  default = "am-prod-infra"
}

variable "secret_name" {
  type    = string
  default = "am-r2-db-dump"
}

variable "cloudflare_account_id" {
  type      = string
  default   = ""
  sensitive = true
}

variable "cloudflare_api_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Optional Bearer token (often list-only for R2)."
}

variable "cloudflare_email" {
  type      = string
  default   = ""
  sensitive = true
}

variable "cloudflare_api_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Global API Key paired with cloudflare_email (R2 object writes)."
}

variable "postgres_secret_name" {
  type    = string
  default = "postgresql-secret"
}

variable "mongo_secret_name" {
  type    = string
  default = "mongodb"
}

variable "redis_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Redis requirepass (from stores random_password); stored in dump secret."
}

variable "pg_databases" {
  type    = string
  default = "platform am_subscription user_platform lago"
}

locals {
  create = var.enabled
  # Prefer explicit CF vars; empty means do not create/manage the secret (pre-created).
  manage_secret = local.create && var.cloudflare_account_id != "" && (
    (var.cloudflare_email != "" && var.cloudflare_api_key != "") ||
    var.cloudflare_api_token != ""
  )
}

resource "null_resource" "build_and_load_image" {
  count = local.create ? 1 : 0

  triggers = {
    dockerfile = filesha256("${path.module}/Dockerfile")
    script     = filesha256("${path.module}/dump.sh")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-BASH
      set -euo pipefail
      CTX="${path.module}"
      docker build -t ${var.image} "$CTX"
      kind load docker-image ${var.image} --name ${var.kind_cluster_name}
      echo "loaded ${var.image} into kind/${var.kind_cluster_name}"
    BASH
  }
}

resource "kubernetes_service_account_v1" "dump" {
  count = local.create ? 1 : 0
  metadata {
    name      = var.service_account_name
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name" = "am-r2-db-dump"
      "am.io/dump"             = var.prefix
    }
  }
}

resource "kubernetes_secret_v1" "dump" {
  count = local.manage_secret ? 1 : 0
  metadata {
    name      = var.secret_name
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name" = "am-r2-db-dump"
      "am.io/dump"             = var.prefix
    }
  }
  data = merge(
    {
      CLOUDFLARE_ACCOUNT_ID = var.cloudflare_account_id
      REDIS_PASSWORD        = var.redis_password
    },
    var.cloudflare_api_token != "" ? { CLOUDFLARE_API_TOKEN = var.cloudflare_api_token } : {},
    var.cloudflare_email != "" ? { CLOUDFLARE_EMAIL = var.cloudflare_email } : {},
    var.cloudflare_api_key != "" ? { CLOUDFLARE_API_KEY = var.cloudflare_api_key } : {},
  )
  type = "Opaque"
}

resource "kubernetes_cron_job_v1" "dump" {
  count = local.create ? 1 : 0

  depends_on = [
    null_resource.build_and_load_image,
    kubernetes_service_account_v1.dump,
  ]

  metadata {
    name      = "am-r2-db-dump"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name" = "am-r2-db-dump"
      "am.io/dump"             = var.prefix
    }
  }

  spec {
    schedule                      = var.schedule
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 2
    failed_jobs_history_limit     = 3
    job_template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "am-r2-db-dump"
          "am.io/dump"             = var.prefix
        }
      }
      spec {
        backoff_limit              = 1
        ttl_seconds_after_finished = 86400
        template {
          metadata {
            labels = {
              "app.kubernetes.io/name" = "am-r2-db-dump"
              "am.io/dump"             = var.prefix
            }
          }
          spec {
            service_account_name = var.service_account_name
            restart_policy       = "OnFailure"
            container {
              name              = "dump"
              image             = var.image
              image_pull_policy = "IfNotPresent"
              env {
                name  = "R2_BUCKET"
                value = var.r2_bucket
              }
              env {
                name  = "DUMP_PREFIX"
                value = var.prefix
              }
              env {
                name  = "NAMESPACE"
                value = var.namespace
              }
              env {
                name  = "PG_DATABASES"
                value = var.pg_databases
              }
              env {
                name = "CLOUDFLARE_ACCOUNT_ID"
                value_from {
                  secret_key_ref {
                    name = var.secret_name
                    key  = "CLOUDFLARE_ACCOUNT_ID"
                  }
                }
              }
              env {
                name = "CLOUDFLARE_API_TOKEN"
                value_from {
                  secret_key_ref {
                    name     = var.secret_name
                    key      = "CLOUDFLARE_API_TOKEN"
                    optional = true
                  }
                }
              }
              env {
                name = "CLOUDFLARE_EMAIL"
                value_from {
                  secret_key_ref {
                    name     = var.secret_name
                    key      = "CLOUDFLARE_EMAIL"
                    optional = true
                  }
                }
              }
              env {
                name = "CLOUDFLARE_API_KEY"
                value_from {
                  secret_key_ref {
                    name     = var.secret_name
                    key      = "CLOUDFLARE_API_KEY"
                    optional = true
                  }
                }
              }
              env {
                name = "PGPASSWORD"
                value_from {
                  secret_key_ref {
                    name = var.postgres_secret_name
                    key  = "POSTGRES_PASSWORD"
                  }
                }
              }
              env {
                name = "PGUSER"
                value_from {
                  secret_key_ref {
                    name = var.postgres_secret_name
                    key  = "POSTGRES_USER"
                  }
                }
              }
              env {
                name = "MONGO_PASSWORD"
                value_from {
                  secret_key_ref {
                    name = var.mongo_secret_name
                    key  = "mongodb-root-password"
                  }
                }
              }
              env {
                name  = "MONGO_USER"
                value = "admin"
              }
              env {
                name = "REDIS_PASSWORD"
                value_from {
                  secret_key_ref {
                    name = var.secret_name
                    key  = "REDIS_PASSWORD"
                  }
                }
              }
              resources {
                requests = {
                  cpu    = "100m"
                  memory = "256Mi"
                }
                limits = {
                  cpu    = "2"
                  memory = "2Gi"
                }
              }
            }
          }
        }
      }
    }
  }
}

output "cronjob_name" {
  value = local.create ? kubernetes_cron_job_v1.dump[0].metadata[0].name : null
}

output "image" {
  value = local.create ? var.image : null
}
