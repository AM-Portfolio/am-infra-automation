# LiteLLM in NS am-ai. Attach: PG platform / user litellm.

locals {
  domain_suffix = var.environment == "prod" ? "" : "-${var.environment}"
  ui_host       = "litellm${local.domain_suffix}.${var.root_domain}"
  database_url  = "postgresql://${var.db_user}:${urlencode(var.db_password)}@${var.db_host}:5432/${var.db_name}?options=-csearch_path%3D${var.db_schema}"
  master_key    = coalesce(var.master_key, random_password.master[0].result)
}

resource "random_password" "master" {
  count            = var.master_key == "" ? 1 : 0
  length           = 32
  special          = false
  override_special = ""
}

resource "kubernetes_secret" "litellm" {
  metadata {
    name      = "litellm-secrets"
    namespace = var.namespace
  }
  data = {
    DATABASE_URL       = local.database_url
    LITELLM_MASTER_KEY = local.master_key
  }
}

resource "kubernetes_deployment" "litellm" {
  metadata {
    name      = "litellm"
    namespace = var.namespace
    labels    = { app = "litellm" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "litellm" } }
    template {
      metadata { labels = { app = "litellm" } }
      spec {
        container {
          name  = "litellm"
          image = var.image
          port { container_port = 4000 }
          resources {
            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }
            limits = {
              cpu    = var.cpu_limit
              memory = var.memory_limit
            }
          }
          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.litellm.metadata[0].name
                key  = "DATABASE_URL"
              }
            }
          }
          env {
            name = "LITELLM_MASTER_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.litellm.metadata[0].name
                key  = "LITELLM_MASTER_KEY"
              }
            }
          }
          env {
            name  = "STORE_MODEL_IN_DB"
            value = "True"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "litellm" {
  metadata {
    name      = "litellm"
    namespace = var.namespace
  }
  spec {
    selector = { app = "litellm" }
    port {
      port        = 4000
      target_port = 4000
    }
  }
}

output "ui_host" { value = local.ui_host }
