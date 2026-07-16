# ==============================================================================
# Authentik Persistence Layer (Identity Backend)
# ==============================================================================
# Deploys dedicated PostgreSQL and Redis for Authentik core.
# Uses official Docker Hub images for security and stability.
# ==============================================================================

# 1. PostgreSQL (Backend)
resource "kubernetes_persistent_volume_claim" "postgres_data" {
  metadata {
    name      = "authentik-postgres-data"
    namespace = var.namespace
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "5Gi" }
    }
  }
  wait_until_bound = false
}

resource "kubernetes_stateful_set" "postgres" {
  metadata {
    name      = "authentik-postgres"
    namespace = var.namespace
    labels    = { app = "authentik-postgres" }
  }
  spec {
    service_name = "authentik-postgres"
    replicas     = 1
    selector { match_labels = { app = "authentik-postgres" } }
    template {
      metadata { labels = { app = "authentik-postgres" } }
      spec {
        container {
          name  = "postgres"
          image = "postgres:15-alpine"
          port { container_port = 5432 }
          env {
            name  = "POSTGRES_PASSWORD"
            value = var.postgres_password
          }
          env {
            name  = "POSTGRES_USER"
            value = "authentik"
          }
          env {
            name  = "POSTGRES_DB"
            value = "authentik"
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
            sub_path   = "postgres"
          }
          resources {
            requests = {
              memory = "256Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "512Mi"
              cpu    = "500m"
            }
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.postgres_data.metadata[0].name
          }
        }
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_service" "postgres" {
  metadata {
    name      = "authentik-postgres"
    namespace = var.namespace
  }
  spec {
    selector = { app = "authentik-postgres" }
    port {
      port        = 5432
      target_port = 5432
    }
    cluster_ip = "None" # Headless service for StatefulSet
  }
}

resource "kubernetes_service" "postgres_exposer" {
  metadata {
    name      = "authentik-postgres-exposer"
    namespace = var.namespace
  }
  spec {
    type     = "NodePort"
    selector = { app = "authentik-postgres" }
    port {
      port        = 5432
      target_port = 5432
      node_port   = 30543
    }
  }
}

# 2. Redis (Cache)
resource "kubernetes_persistent_volume_claim" "redis_data" {
  metadata {
    name      = "authentik-redis-data"
    namespace = var.namespace
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "1Gi" }
    }
  }
  wait_until_bound = false
}

resource "kubernetes_deployment" "redis" {
  metadata {
    name      = "authentik-redis"
    namespace = var.namespace
    labels    = { app = "authentik-redis" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "authentik-redis" } }
    template {
      metadata { labels = { app = "authentik-redis" } }
      spec {
        container {
          name  = "redis"
          image = "redis:7-alpine"
          port { container_port = 6379 }
          command = ["redis-server", "--save", "60", "1", "--loglevel", "warning"]
          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
          resources {
            requests = {
              memory = "64Mi"
              cpu    = "50m"
            }
            limits = {
              memory = "256Mi"
              cpu    = "250m"
            }
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.redis_data.metadata[0].name
          }
        }
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_service" "redis" {
  metadata {
    name      = "authentik-redis"
    namespace = var.namespace
  }
  spec {
    selector = { app = "authentik-redis" }
    port {
      port        = 6379
      target_port = 6379
    }
  }
}

# 3. VAULT SYNC (Sync Automation Token back to Vault)
resource "vault_generic_secret" "terraform_token" {
  path = "secret/infra/identity/automation"
  data_json = jsonencode({
    terraform_token = authentik_token.terraform.key
  })
  
  # Ensure token exists before syncing
  depends_on = [authentik_token.terraform]
}
