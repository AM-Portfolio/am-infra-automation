# ------------------------------------------------------------------------------
# MinIO Object Storage (StatefulSet + HostPath Persistence)
# ------------------------------------------------------------------------------

# 1. Data Immortality: Explicit HostPath Allocation
resource "kubernetes_persistent_volume" "minio_pv" {
  metadata {
    name = "minio-pv-immortal"
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
        path = "/var/am-infra/data/minio"
        type = "DirectoryOrCreate"
      }
    }
  }
  lifecycle {
    ignore_changes = [spec[0].capacity]
  }
}

resource "kubernetes_persistent_volume_claim" "minio_pvc" {
  metadata {
    name      = "minio-pvc-immortal"
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
    volume_name = kubernetes_persistent_volume.minio_pv.metadata[0].name
  }
  lifecycle {
    ignore_changes = [spec[0].resources]
  }
}

# 2. MinIO Root Credentials
resource "kubernetes_secret" "minio_secret" {
  metadata {
    name      = "minio-secret"
    namespace = var.namespace
  }
  data = {
    MINIO_ROOT_USER     = var.minio_root_user
    MINIO_ROOT_PASSWORD = var.minio_root_password
  }
}

# 3. MinIO StatefulSet
resource "kubernetes_stateful_set" "minio" {
  metadata {
    name      = "minio"
    namespace = var.namespace
    labels    = { app = "minio" }
  }
  spec {
    service_name = "minio"
    replicas     = 1
    selector {
      match_labels = { app = "minio" }
    }
    template {
      metadata {
        labels = { app = "minio" }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "9000"
          "prometheus.io/path"   = "/minio/v2/metrics/cluster"
        }
      }
      spec {
        container {
          name  = "minio"
          image = var.image
          args  = ["server", "/data", "--console-address", ":9001"]
          
          port {
            name           = "api"
            container_port = 9000
          }
          port {
            name           = "console"
            container_port = 9001
          }

          env_from {
            secret_ref { name = kubernetes_secret.minio_secret.metadata[0].name }
          }

          env {
            name  = "MINIO_PROMETHEUS_AUTH_TYPE"
            value = "public"
          }

          env {
            name  = "MINIO_BROWSER_REDIRECT_URL"
            value = local.minio_console_url
          }

          # Keycloak OpenID (native MinIO console button)
          dynamic "env" {
            for_each = local.minio_oidc_ready ? [
              { name = "MINIO_IDENTITY_OPENID_DISPLAY_NAME", value = local.oidc_display_name },
              { name = "MINIO_IDENTITY_OPENID_CONFIG_URL", value = local.oidc_config_url },
              { name = "MINIO_IDENTITY_OPENID_CLIENT_ID", value = local.final_oidc_client_id },
              { name = "MINIO_IDENTITY_OPENID_CLIENT_SECRET", value = local.final_oidc_client_secret },
              { name = "MINIO_IDENTITY_OPENID_SCOPES", value = "openid,profile,email,roles,groups" },
              { name = "MINIO_IDENTITY_OPENID_REDIRECT_URI", value = "${local.minio_console_url}/oauth_callback" },
              { name = "MINIO_IDENTITY_OPENID_CLAIM_NAME", value = "groups" },
            ] : []
            content {
              name  = env.value.name
              value = env.value.value
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
          
          resources {
            requests = { memory = var.memory_request, cpu = var.cpu_request }
            limits   = { memory = var.memory_limit, cpu = var.cpu_limit }
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.minio_pvc.metadata[0].name
          }
        }
      }
    }
  }

  wait_for_rollout = true
  timeouts { create = "8m" }

  lifecycle {
    prevent_destroy = true
  }
}

# 4. Service
resource "kubernetes_service" "minio" {
  metadata {
    name      = "minio"
    namespace = var.namespace
  }
  spec {
    type     = "NodePort"
    selector = { app = "minio" }
    port {
      name        = "api"
      port        = 9000
      target_port = 9000
      node_port   = 30900
    }
    port {
      name        = "console"
      port        = 9001
      target_port = 9001
      node_port   = 30901
    }
  }
}

# Optional KV fallback only when client secret is not passed at apply time.
data "vault_kv_secret_v2" "oidc" {
  count = var.oidc_enabled && var.oidc_client_secret == "" ? 1 : 0
  mount = "apps"
  name  = "${var.environment}/oidc/minio"
}

locals {
  oidc_data                = length(data.vault_kv_secret_v2.oidc) > 0 ? data.vault_kv_secret_v2.oidc[0].data : {}
  final_oidc_client_id     = var.oidc_client_id != "" ? var.oidc_client_id : lookup(local.oidc_data, "client_id", "minio")
  final_oidc_client_secret = var.oidc_client_secret != "" ? var.oidc_client_secret : lookup(local.oidc_data, "client_secret", "")
  final_oidc_issuer_url    = var.oidc_issuer_url != "" ? var.oidc_issuer_url : lookup(local.oidc_data, "issuer_url", "")
  minio_oidc_ready         = var.oidc_enabled && local.final_oidc_client_id != "" && local.final_oidc_client_secret != "" && local.final_oidc_issuer_url != ""
  oidc_is_keycloak         = can(regex("/realms/", local.final_oidc_issuer_url))
  oidc_display_name        = local.oidc_is_keycloak ? "Keycloak" : "Authentik SSO"
  oidc_config_url = local.oidc_is_keycloak ? (
    "${trimsuffix(local.final_oidc_issuer_url, "/")}/.well-known/openid-configuration"
    ) : (
    "${trimsuffix(local.final_oidc_issuer_url, "/")}/application/o/minio/.well-known/openid-configuration"
  )
  minio_host = var.environment == "prod" || var.environment == "local" ? (
    var.environment == "local" ? "minio-local.${var.root_domain}" : "minio.${var.root_domain}"
  ) : "minio-${var.environment}.${var.root_domain}"
  minio_console_url = "https://${local.minio_host}"
}
