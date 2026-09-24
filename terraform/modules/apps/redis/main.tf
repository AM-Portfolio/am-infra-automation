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
      storage = var.storage
    }
    volume_mode                      = "Filesystem"
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "manual-hostpath"
    persistent_volume_source {
      host_path {
        path = "/var/am-infra/data/redis"
        type = "DirectoryOrCreate"
      }
    }
  }
  lifecycle {
    ignore_changes = [spec[0].capacity]
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
        storage = var.storage
      }
    }
    volume_name = kubernetes_persistent_volume.redis_pv.metadata[0].name
  }
  lifecycle {
    ignore_changes = [spec[0].resources]
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
    "redis.conf" = "requirepass ${var.redis_password}\nmaxmemory ${var.redis_maxmemory}\nmaxmemory-policy allkeys-lru\n"
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
        node_selector = {
          role = "infra"
        }
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
            requests = { memory = var.memory_request, cpu = var.cpu_request }
            limits   = { memory = var.memory_limit, cpu = var.cpu_limit }
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
    nodeSelector = {
      role = "infra"
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
