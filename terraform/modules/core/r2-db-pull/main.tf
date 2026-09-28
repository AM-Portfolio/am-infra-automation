# TF-managed R2 → DR restore (slave). Builds local image, loads into Kind, CronJob.

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
  default = "30 */6 * * *"
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
  default = "am-r2-db-pull"
}

variable "image" {
  type    = string
  default = "am-r2-db-pull:local"
}

variable "kind_cluster_name" {
  type    = string
  default = "am-dr-infra"
}

variable "secret_name" {
  type    = string
  default = "am-r2-db-pull"
}

variable "cloudflare_account_id" {
  type      = string
  default   = ""
  sensitive = true
}

variable "cloudflare_api_token" {
  type      = string
  default   = ""
  sensitive = true
}

variable "cloudflare_email" {
  type      = string
  default   = ""
  sensitive = true
}

variable "cloudflare_api_key" {
  type      = string
  default   = ""
  sensitive = true
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
  type      = string
  default   = ""
  sensitive = true
}

variable "pg_databases" {
  type    = string
  default = "platform am_subscription user_platform lago"
}

locals {
  create = var.enabled
  manage_secret = local.create && var.cloudflare_account_id != "" && (
    (var.cloudflare_email != "" && var.cloudflare_api_key != "") ||
    var.cloudflare_api_token != ""
  )
}

resource "null_resource" "build_and_load_image" {
  count = local.create ? 1 : 0

  triggers = {
    dockerfile = filesha256("${path.module}/Dockerfile")
    script     = filesha256("${path.module}/pull.sh")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-BASH
      set -euo pipefail
      CTX="${path.module}"
      IMG="${var.image}"
      CLUSTER="${var.kind_cluster_name}"
      REF="docker.io/library/$${IMG}"
      NODE="$${CLUSTER}-control-plane"
      TAR="$${AM_R2_PULL_IMAGE_TAR:-/tmp/am-r2-db-pull.tar}"
      # VPS3 Docker 29 containerd-snapshotter: docker save is broken — use overlay2-host tar.
      if docker info -f '{{json .DriverStatus}}' 2>/dev/null | grep -q 'containerd.snapshotter'; then
        if [ ! -f "$TAR" ] || [ "$$(stat -c%s "$TAR")" -le 1000000 ]; then
          echo "containerd snapshotter host: place overlay2 docker-save tar at $TAR (build on Contabo/VPS1)" >&2
          exit 1
        fi
        kind load image-archive "$TAR" --name "$CLUSTER"
      else
        docker build -t "$IMG" "$CTX"
        kind load docker-image "$IMG" --name "$CLUSTER"
      fi
      echo "loaded $IMG into kind/$CLUSTER"
    BASH
  }
}

resource "kubernetes_service_account_v1" "pull" {
  count = local.create ? 1 : 0
  metadata {
    name      = var.service_account_name
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name" = "am-r2-db-pull"
      "am.io/pull"             = var.prefix
    }
  }
}

resource "kubernetes_secret_v1" "pull" {
  count = local.manage_secret ? 1 : 0
  metadata {
    name      = var.secret_name
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name" = "am-r2-db-pull"
      "am.io/pull"             = var.prefix
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

resource "kubernetes_cron_job_v1" "pull" {
  count = local.create ? 1 : 0

  depends_on = [
    null_resource.build_and_load_image,
    kubernetes_service_account_v1.pull,
  ]

  metadata {
    name      = "am-r2-db-pull"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name" = "am-r2-db-pull"
      "am.io/pull"             = var.prefix
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
          "app.kubernetes.io/name" = "am-r2-db-pull"
          "am.io/pull"             = var.prefix
        }
      }
      spec {
        backoff_limit              = 3
        active_deadline_seconds    = 3600
        ttl_seconds_after_finished = 86400
        template {
          metadata {
            labels = {
              "app.kubernetes.io/name" = "am-r2-db-pull"
              "am.io/pull"             = var.prefix
            }
          }
          spec {
            service_account_name = var.service_account_name
            restart_policy       = "OnFailure"
            container {
              name              = "pull"
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
                name  = "SOURCE_PREFIX"
                value = "${var.prefix}/latest"
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
                  cpu    = "200m"
                  memory = "1Gi"
                }
                limits = {
                  cpu    = "2"
                  memory = "6Gi"
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
  value = local.create ? kubernetes_cron_job_v1.pull[0].metadata[0].name : null
}
