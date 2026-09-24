# OpenProject on platform NS. Attach: PG platform / user openproject.

locals {
  domain_suffix = var.environment == "prod" ? "" : "-${var.environment}"
  ui_host       = "openproject${local.domain_suffix}.${var.root_domain}"
  # Include public so PG extensions (pg_trgm gin_trgm_ops, btree_gist) resolve under schema-only roles.
  database_url  = "postgresql://${var.db_user}:${urlencode(var.db_password)}@${var.db_host}:5432/${var.db_name}?options=-csearch_path%3D${var.db_schema}%2Cpublic"
}

resource "random_id" "sk" {
  byte_length = 32
}

resource "kubernetes_secret" "openproject" {
  metadata {
    name      = "openproject-secret"
    namespace = var.namespace
  }
  data = {
    secret-key-base = random_id.sk.hex
    DATABASE_URL    = local.database_url
  }
}

resource "kubernetes_deployment" "openproject" {
  metadata {
    name      = "openproject"
    namespace = var.namespace
    labels    = { app = "openproject" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "openproject" } }
    template {
      metadata { labels = { app = "openproject" } }
      spec {
        container {
          name  = "openproject"
          image = var.image
          port { container_port = 80 }
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
            name  = "OPENPROJECT_HOST__NAME"
            value = local.ui_host
          }
          env {
            name  = "OPENPROJECT_HTTPS"
            value = "true"
          }
          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.openproject.metadata[0].name
                key  = "DATABASE_URL"
              }
            }
          }
          env {
            name = "SECRET_KEY_BASE"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.openproject.metadata[0].name
                key  = "secret-key-base"
              }
            }
          }
          env {
            name  = "OPENPROJECT_RAILS__RELATIVE__URL__ROOT"
            value = ""
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "openproject" {
  metadata {
    name      = "openproject"
    namespace = var.namespace
  }
  spec {
    selector = { app = "openproject" }
    port {
      port        = 80
      target_port = 80
    }
  }
}

output "ui_host" { value = local.ui_host }
