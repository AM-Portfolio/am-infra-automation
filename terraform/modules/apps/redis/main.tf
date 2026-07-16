# ------------------------------------------------------------------------------
# Redis & Redis Commander UI (Native Helm Deployment)
# ------------------------------------------------------------------------------

# ── Data Immortality: Explicit HostPath Allocation ─────────────────────────
resource "kubernetes_persistent_volume" "redis_pv" {
  metadata {
    name = "redis-pv-immortal"
  }
  spec {
    capacity = {
      storage = "1Gi"
    }
    volume_mode                      = "Filesystem"
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "manual-hostpath"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "redis_pvc" {
  metadata {
    name      = "redis-pvc-immortal"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "manual-hostpath"
    resources {
      requests = {
        storage = "1Gi"
      }
    }
    volume_name = kubernetes_persistent_volume.redis_pv.metadata[0].name
  }
}


# ------------------------------------------------------------------------------
# Redis — Official image (avoids bitnami/os-shell Docker Hub breakage)
# ------------------------------------------------------------------------------
resource "kubernetes_config_map" "redis_config" {
  metadata {
    name      = "redis-config"
    namespace = var.namespace
  }
  data = {
    "redis.conf" = "requirepass ${var.redis_password}\nmaxmemory 128mb\nmaxmemory-policy allkeys-lru\n"
  }
}

resource "kubernetes_stateful_set" "redis" {
  metadata {
    name      = "redis-master"
    namespace = var.namespace
    labels    = { app = "redis" }
  }
  spec {
    service_name = "redis-master"
    replicas     = 1
    selector {
      match_labels = { app = "redis" }
    }
    template {
      metadata {
        labels = { app = "redis" }
      }
      spec {
        container {
          name  = "redis"
          image = "redis:7.2-alpine"
          command = ["redis-server", "/etc/redis/redis.conf"]
          port { container_port = 6379 }
          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
          volume_mount {
            name       = "config"
            mount_path = "/etc/redis"
          }
          resources {
            requests = { memory = "64Mi", cpu = "25m" }
            limits   = { memory = "256Mi", cpu = "200m" }
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.redis_pvc.metadata[0].name
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.redis_config.metadata[0].name
          }
        }
      }
    }
  }
  wait_for_rollout = true
  timeouts { create = "5m" }

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_service" "redis_master" {
  metadata {
    name      = "redis-master"
    namespace = var.namespace
  }
  spec {
    type     = "NodePort"
    selector = { app = "redis" }
    port {
      port        = 6379
      target_port = 6379
      node_port   = 30379
    }
  }
}

# Redis Commander UI Installation
resource "helm_release" "redis_commander" {
  name       = "redis-commander"
  repository = "https://kfirfer.github.io/charts/"
  chart      = "redis-commander"
  namespace  = var.namespace
  version    = "0.1.16"

  values = [yamlencode({
    redis = {
      host     = "redis-master"
      password = var.redis_password
    }
    env = [
      { name = "REDIS_HOSTS", value = "local:redis-master:6379:0:${var.redis_password}" }
    ]
    ingress = {
      enabled = false # Controlled by our explicit Gateway routes instead
    }
  })]

  wait = true

  lifecycle {
    prevent_destroy = true
  }
}
