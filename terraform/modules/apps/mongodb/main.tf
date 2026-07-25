# ------------------------------------------------------------------------------
# MongoDB & Mongo Express (Native Helm Deployment)
# ------------------------------------------------------------------------------

# ── Data Immortality: Explicit HostPath Allocation ─────────────────────────
resource "kubernetes_persistent_volume" "mongo_pv" {
  metadata {
    name = "mongo-pv-immortal"
  }
  spec {
    capacity = {
      storage = "2Gi"
    }
    volume_mode                      = "Filesystem"
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "manual-hostpath"
    persistent_volume_source {
      host_path {
        path = "/var/am-infra/data/mongo"
        type = "DirectoryOrCreate"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "mongo_pvc" {
  metadata {
    name      = "mongo-pvc-immortal"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "manual-hostpath"
    resources {
      requests = {
        storage = "2Gi"
      }
    }
    volume_name = kubernetes_persistent_volume.mongo_pv.metadata[0].name
  }
}

resource "helm_release" "mongodb" {
  name       = "mongodb"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "mongodb"
  namespace  = var.namespace
  version    = "13.15.2"

  values = [yamlencode({
    auth = {
      enabled       = true
      rootUser      = var.mongo_root_user
      rootPassword  = var.mongo_root_password
    }
    architecture = "standalone"
    nodeSelector = {
      role = "infra"
    }
    image = {
      registry   = "docker.io"
      repository = "bitnamilegacy/mongodb"
      tag        = "7.0"
    }
    persistence = {
      enabled       = true
      existingClaim = kubernetes_persistent_volume_claim.mongo_pvc.metadata[0].name
    }
    volumePermissions = {
      enabled = true
      image = {
        registry   = "docker.io"
        repository = "library/ubuntu"
        tag        = "latest"
      }
    }

    # 🌐 External Access: Expose MongoDB via NodePort for port-exposer
    service = {
      type = "NodePort"
      nodePorts = {
        mongodb = 30017
      }
    }

    # ENTERPRISE PREVENTION LOCK: Do NOT delete the MongoDB cluster accidentally
    annotations = {
      "helm.sh/resource-policy" = "keep"
    }
  })]

  wait    = true
  timeout = 600

  lifecycle {
    prevent_destroy = true
  }
}

# Mongo Express UI Installation
resource "helm_release" "mongo_express" {
  name       = "mongo-express"
  repository = "https://cowboysysop.github.io/charts/"
  chart      = "mongo-express"
  namespace  = var.namespace
  version    = "7.0.0"

  values = [yamlencode({
    mongodbAdminUsername = var.mongo_root_user
    mongodbAdminPassword = var.mongo_root_password
    mongodbServer        = "mongodb.${var.namespace}.svc.cluster.local"
    mongodbPort          = 27017
    mongodbEnableAdmin   = true
    nodeSelector = {
      role = "infra"
    }
    ingress = {
      enabled = false # Controlled by our explicit Gateway routes instead
    }
  })]

  wait = true

  lifecycle {
    prevent_destroy = true
  }
}
