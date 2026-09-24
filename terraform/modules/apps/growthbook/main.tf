# GrowthBook. Attach: Mongo database platform, user growthbook.
# Pin matches am-infra kind-am-preprod lab: chart + image 4.4.0 (pm2 entrypoint).

locals {
  domain_suffix = var.environment == "prod" ? "" : "-${var.environment}"
  ui_host       = "growthbook${local.domain_suffix}.${var.root_domain}"
  mongo_uri     = "mongodb://${var.mongo_user}:${urlencode(var.mongo_password)}@${var.mongo_host}:27017/${var.mongo_db}?authSource=admin"
}

resource "random_password" "jwt" {
  length  = 64
  special = false
}

resource "random_password" "encryption" {
  length  = 64
  special = false
}

resource "kubernetes_secret" "mongo" {
  metadata {
    name      = "growthbook-mongodb"
    namespace = var.namespace
  }
  data = {
    uri            = local.mongo_uri
    jwt-secret     = random_password.jwt.result
    encryption-key = random_password.encryption.result
  }
}

resource "helm_release" "growthbook" {
  name             = "growthbook"
  repository       = "oci://ghcr.io/growthbook/charts"
  chart            = "growthbook"
  namespace        = var.namespace
  version          = var.chart_version
  create_namespace = false
  wait             = true
  timeout          = 900

  values = [yamlencode({
    mongodb = { enabled = false }
    frontend = {
      image = {
        repository = "growthbook/growthbook"
        tag        = var.image_tag
      }
      # Chart 4.4.x default: pm2-runtime (matches growthbook/growthbook:4.4.0).
      resources = {
        requests = { cpu = var.frontend_cpu_request, memory = var.frontend_memory_request }
        limits   = { cpu = var.frontend_cpu_limit, memory = var.frontend_memory_limit }
      }
      env = [
        { name = "APP_ORIGIN", value = "https://${local.ui_host}" },
        { name = "API_HOST", value = "https://${local.ui_host}" },
        { name = "NODE_ENV", value = "production" },
      ]
      livenessProbe = {
        httpGet             = { path = "/", port = "http" }
        initialDelaySeconds = 60
        periodSeconds       = 20
        failureThreshold    = 6
      }
      readinessProbe = {
        httpGet             = { path = "/", port = "http" }
        initialDelaySeconds = 20
        periodSeconds       = 10
        failureThreshold    = 12
      }
    }
    backend = {
      image = {
        repository = "growthbook/growthbook"
        tag        = var.image_tag
      }
      mongodbEnabled = false
      mongodbUri     = local.mongo_uri
      volumeClaim    = { enabled = false }
      resources = {
        requests = { cpu = var.backend_cpu_request, memory = var.backend_memory_request }
        limits   = { cpu = var.backend_cpu_limit, memory = var.backend_memory_limit }
      }
      env = [
        { name = "MONGODB_URI", valueFrom = { secretKeyRef = { name = kubernetes_secret.mongo.metadata[0].name, key = "uri" } } },
        { name = "APP_ORIGIN", value = "https://${local.ui_host}" },
        { name = "API_HOST", value = "https://${local.ui_host}" },
        { name = "NODE_ENV", value = "production" },
        {
          name = "JWT_SECRET"
          valueFrom = { secretKeyRef = { name = kubernetes_secret.mongo.metadata[0].name, key = "jwt-secret" } }
        },
        {
          name = "ENCRYPTION_KEY"
          valueFrom = { secretKeyRef = { name = kubernetes_secret.mongo.metadata[0].name, key = "encryption-key" } }
        },
      ]
      livenessProbe = {
        httpGet             = { path = "/healthcheck", port = "http" }
        initialDelaySeconds = 45
        periodSeconds       = 20
        failureThreshold    = 6
      }
      readinessProbe = {
        httpGet             = { path = "/healthcheck", port = "http" }
        initialDelaySeconds = 20
        periodSeconds       = 10
        failureThreshold    = 12
      }
    }
    ingress = { enabled = false }
  })]
}

output "ui_host" { value = local.ui_host }
