# Lago API + front in NS billing. Not am-subscription.
# PG: dedicated DB lago (OWNER lago, CREATEDB for Helm db:create) via postgres-<env>.asrax.in
# Redis: redis-<env>.asrax.in (DB index var.redis_db).

locals {
  domain_suffix = var.environment == "prod" ? "" : "-${var.environment}"
  ui_host       = "lago${local.domain_suffix}.${var.root_domain}"
  api_host      = "lago${local.domain_suffix}.${var.root_domain}"
  database_url  = "postgresql://${var.db_user}:${urlencode(var.db_password)}@${var.db_host}:5432/${var.db_name}"
  redis_url     = "redis://:${urlencode(var.redis_password)}@${var.redis_host}:6379/${var.redis_db}"
}

resource "helm_release" "lago" {
  name             = "lago"
  repository       = "https://getlago.github.io/lago-helm-charts"
  chart            = "lago"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = false
  wait             = true
  timeout          = 900

  values = [yamlencode({
    apiUrl   = "https://${local.api_host}"
    frontUrl = "https://${local.ui_host}"

    global = {
      databaseUrl = local.database_url
      redisUrl    = local.redis_url
      segment     = { enabled = false }
      s3          = { enabled = false }
      smtp        = { enabled = false }
      signup      = { enabled = true }
      pdf         = { enabled = false }
      googleAuth  = { enabled = false }
      ingress     = { enabled = false }
      clickhouse  = { enabled = false }
    }

    front = {
      replicas = 1
      resources = {
        requests = {
          cpu    = var.front_cpu_request
          memory = var.front_memory_request
        }
        limits = {
          cpu    = var.front_cpu_limit
          memory = var.front_memory_limit
        }
      }
    }

    api = {
      replicas = 1
      resources = {
        requests = {
          cpu    = var.api_cpu_request
          memory = var.api_memory_request
        }
        limits = {
          cpu    = var.api_cpu_limit
          memory = var.api_memory_limit
        }
      }
    }

    # Chart defaults request 1100m CPU per worker (~7.7 cores) — too heavy for kind laptop.
    worker = {
      resources = { requests = { cpu = "50m", memory = "256Mi" }, limits = { cpu = "1", memory = "1Gi" } }
    }
    eventsWorker = {
      resources = { requests = { cpu = "50m", memory = "256Mi" }, limits = { cpu = "1", memory = "1Gi" } }
    }
    clockWorker = {
      resources = { requests = { cpu = "50m", memory = "256Mi" }, limits = { cpu = "1", memory = "1Gi" } }
    }
    billingWorker = {
      resources = { requests = { cpu = "50m", memory = "256Mi" }, limits = { cpu = "1", memory = "1Gi" } }
    }
    pdfWorker = {
      resources = { requests = { cpu = "50m", memory = "256Mi" }, limits = { cpu = "1", memory = "1Gi" } }
    }
    webhookWorker = {
      resources = { requests = { cpu = "50m", memory = "256Mi" }, limits = { cpu = "1", memory = "1Gi" } }
    }
    paymentWorker = {
      resources = { requests = { cpu = "50m", memory = "256Mi" }, limits = { cpu = "1", memory = "1Gi" } }
    }
    pdf = {
      resources = { requests = { cpu = "50m", memory = "512Mi" }, limits = { cpu = "1", memory = "2Gi" } }
    }
    clock = {
      resources = { requests = { cpu = "50m", memory = "128Mi" }, limits = { cpu = "500m", memory = "512Mi" } }
    }
  })]
}

output "ui_host" {
  value = local.ui_host
}
