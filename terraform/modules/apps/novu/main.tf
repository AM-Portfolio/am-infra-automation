# Novu (api/worker/web/ws) from am-platform Helm chart.
# NS notification; Mongo DB novu + Redis DB index 2 on fleet stores.
# Not am-notification (apps Phase 4+).

locals {
  domain_suffix = var.environment == "prod" ? "" : "-${var.environment}"
  ui_host       = "novu${local.domain_suffix}.${var.root_domain}"
  chart_path    = var.chart_path != "" ? var.chart_path : "${path.module}/../../../../../am-platform/automation/helm/novu"
  storage_key   = coalesce(var.storage_key, random_password.storage[0].result)
  jwt_secret    = coalesce(var.jwt_secret, random_password.jwt[0].result)
  novu_secret   = coalesce(var.novu_secret_key, random_password.novu[0].result)
  mongo_url     = "mongodb://${var.mongo_user}:${urlencode(var.mongo_password)}@${var.mongo_host}:27017/${var.mongo_db}?authSource=admin"
}

resource "random_password" "storage" {
  count   = var.storage_key == "" ? 1 : 0
  length  = 32
  special = false
}

resource "random_password" "jwt" {
  count   = var.jwt_secret == "" ? 1 : 0
  length  = 32
  special = false
}

resource "random_password" "novu" {
  count   = var.novu_secret_key == "" ? 1 : 0
  length  = 32
  special = false
}

resource "helm_release" "novu" {
  name             = "novu"
  chart            = local.chart_path
  namespace        = var.namespace
  create_namespace = false
  wait             = true
  timeout          = 1200
  dependency_update = true

  values = [yamlencode({
    ingress = { enabled = false }
    service = { type = "ClusterIP" }

    mongodb = { enabled = false }
    redis   = { enabled = false }

    externalDataStores = {
      enabled       = true
      mongoUrl      = local.mongo_url
      redisHost     = var.redis_host
      redisPort     = "6379"
      redisPassword = var.redis_password
    }

    web = {
      replicaCount = 1
      port         = 4200
      resources = {
        requests = { cpu = var.web_cpu_request, memory = var.web_memory_request }
        limits   = { cpu = var.web_cpu_limit, memory = var.web_memory_limit }
      }
      widgets = {
        embedPath = "https://${local.ui_host}/embed.umd.min.js"
        url       = "https://${local.ui_host}"
      }
    }
    api = {
      replicaCount = 1
      port         = 3000
      # Chart templates dereference .livenessProbe.*; nil map fails helm render.
      livenessProbe = {
        initialDelaySeconds = 30
        periodSeconds       = 10
        timeoutSeconds      = 5
        failureThreshold    = 3
      }
      readinessProbe = {
        initialDelaySeconds = 5
        periodSeconds       = 10
      }
      resources = {
        requests = { cpu = var.api_cpu_request, memory = var.api_memory_request }
        limits   = { cpu = var.api_cpu_limit, memory = var.api_memory_limit }
      }
    }
    worker = {
      replicaCount = 1
      resources = {
        requests = { cpu = var.worker_cpu_request, memory = var.worker_memory_request }
        limits   = { cpu = var.worker_cpu_limit, memory = var.worker_memory_limit }
      }
    }
    ws = {
      replicaCount = 1
      port         = 3002
      resources = {
        requests = { cpu = var.ws_cpu_request, memory = var.ws_memory_request }
        limits   = { cpu = var.ws_cpu_limit, memory = var.ws_memory_limit }
      }
    }

    global = {
      env = {
        nodeEnv                 = "production"
        apiRootUrl              = "https://${local.ui_host}"
        frontBaseUrl            = "https://${local.ui_host}"
        wsRootUrl               = "https://${local.ui_host}"
        disableUserRegistration = false
        mongodb = {
          maxPoolSize = 50
          minPoolSize = 5
        }
        secret = {
          novuSecretKey = local.novu_secret
          jwtSecret     = local.jwt_secret
          storageKey    = local.storage_key
        }
        s3 = {
          localStack = true
          bucketName = "novu"
          region     = "us-east-1"
        }
        aws = {
          accessKeyId     = "local"
          secretAccessKey = "local"
        }
        sentry   = { dsn = "" }
        newRelic = { appName = "novu", licenseKey = "" }
      }
    }
  })]
}

output "ui_host" { value = local.ui_host }
