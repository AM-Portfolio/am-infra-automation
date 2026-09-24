# n8n on fleet Postgres + Redis (queue mode). Attach: platform / user n8n / schema n8n.

locals {
  domain_suffix  = var.environment == "prod" ? "" : "-${var.environment}"
  ui_host        = "n8n${local.domain_suffix}.${var.root_domain}"
  encryption_key = coalesce(var.encryption_key, random_password.encryption[0].result)
}

resource "random_password" "encryption" {
  count   = var.encryption_key == "" ? 1 : 0
  length  = 32
  special = false
}

resource "kubernetes_secret" "n8n" {
  metadata {
    name      = "n8n-secrets"
    namespace = var.namespace
  }
  data = {
    password           = var.db_password
    redis-password     = var.redis_password
    N8N_ENCRYPTION_KEY = local.encryption_key
    N8N_HOST           = local.ui_host
    N8N_PORT           = "5678"
    N8N_PROTOCOL       = "https"
  }
}

resource "helm_release" "n8n" {
  name             = "n8n"
  repository       = "oci://ghcr.io/n8n-io/n8n-helm-chart"
  chart            = "n8n"
  namespace        = var.namespace
  version          = var.chart_version
  create_namespace = false
  wait             = true
  timeout          = 900

  values = [yamlencode({
    image = {
      repository = var.image_repository
      tag        = var.image_tag
      pullPolicy = "IfNotPresent"
    }

    queueMode = {
      enabled            = true
      workerReplicaCount = var.worker_replicas
    }

    webhookProcessor = { enabled = false }

    main = {
      config = {
        n8n = {
          host     = local.ui_host
          protocol = "https"
          port     = 443
        }
      }
      resources = {
        requests = {
          cpu    = var.cpu_request
          memory = var.memory_request
        }
        limits = {
          cpu    = var.cpu_limit
          memory = var.memory_limit
        }
      }
    }

    database = {
      type        = "postgresdb"
      useExternal = true
      host        = var.db_host
      port        = 5432
      database    = var.db_name
      schema      = var.db_schema
      user        = var.db_user
      passwordSecret = {
        name = kubernetes_secret.n8n.metadata[0].name
        key  = "password"
      }
    }

    redis = {
      enabled     = true
      useExternal = true
      host        = var.redis_host
      port        = 6379
      database    = var.redis_db
      passwordSecret = {
        name = kubernetes_secret.n8n.metadata[0].name
        key  = "redis-password"
      }
    }

    persistence = {
      enabled          = true
      size             = "5Gi"
      storageClassName = var.storage_class
    }

    ingress = { enabled = false }

    secretRefs = {
      existingSecret = kubernetes_secret.n8n.metadata[0].name
      env = {
        N8N_ENCRYPTION_KEY = local.encryption_key
        N8N_HOST           = local.ui_host
        N8N_PORT           = "5678"
        N8N_PROTOCOL       = "https"
      }
    }
  })]
}

output "ui_host" { value = local.ui_host }
