# ------------------------------------------------------------------------------
# PostgreSQL & pgAdmin UI (Native Helm Deployment)
# ------------------------------------------------------------------------------

# ── Data Immortality: Explicit HostPath Allocation ─────────────────────────
resource "kubernetes_persistent_volume" "postgres_pv" {
  metadata {
    name = "postgres-pv-immortal"
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
        path = "/var/am-infra/data/postgres"
        type = "DirectoryOrCreate"
      }
    }
  }
  lifecycle {
    ignore_changes = [spec[0].capacity]
  }
}

resource "kubernetes_persistent_volume_claim" "postgres_pvc" {
  metadata {
    name      = "postgres-pvc-immortal"
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
    volume_name = kubernetes_persistent_volume.postgres_pv.metadata[0].name
  }
  lifecycle {
    ignore_changes = [spec[0].resources]
  }
}

# ------------------------------------------------------------------------------
# PostgreSQL — Official image (avoids bitnami/os-shell Docker Hub breakage)
# ------------------------------------------------------------------------------
resource "kubernetes_secret" "postgres_secret" {
  metadata {
    name      = "postgresql-secret"
    namespace = var.namespace
  }
  data = {
    POSTGRES_PASSWORD = var.db_password
    POSTGRES_USER     = var.db_user
    POSTGRES_DB       = var.db_name
  }
}

resource "kubernetes_stateful_set" "postgresql" {
  metadata {
    name      = "postgresql"
    namespace = var.namespace
    labels    = { app = "postgresql" }
  }
  spec {
    service_name = "postgresql"
    replicas     = 1
    selector {
      match_labels = { app = "postgresql" }
    }
    template {
      metadata {
        labels = { app = "postgresql" }
      }
      spec {
        node_selector = {
          role = "infra"
        }
        container {
          name  = "postgresql"
          image = "postgres:16-alpine"
          port { container_port = 5432 }
          env_from {
            secret_ref { name = kubernetes_secret.postgres_secret.metadata[0].name }
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
            sub_path   = "pgdata"
          }
          resources {
            requests = { memory = var.memory_request, cpu = var.cpu_request }
            limits   = { memory = var.memory_limit, cpu = var.cpu_limit }
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.postgres_pvc.metadata[0].name
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

resource "kubernetes_service" "postgresql" {
  metadata {
    name      = "postgresql"
    namespace = var.namespace
  }
  spec {
    type     = "NodePort"
    selector = { app = "postgresql" }
    port {
      port        = 5432
      target_port = 5432
      node_port   = 30432
    }
  }
}

# ------------------------------------------------------------------------------
# OIDC Configuration Fetch (from Vault)
# ------------------------------------------------------------------------------
data "vault_kv_secret_v2" "oidc" {
  count = var.oidc_enabled ? 1 : 0
  mount = "secret"
  name  = "${var.environment}/infra/oidc-data-stores"
}

locals {
  oidc_data      = var.oidc_enabled ? data.vault_kv_secret_v2.oidc[0].data : {}
  authentik_host = "authentik${var.environment == "prod" ? "" : "-${var.environment}"}.${var.root_domain}"

  # pgAdmin OIDC Environment (Extracted for Checksum)
  # IMPORTANT: Values are wrapped in double quotes for Python config_distro.py compatibility
  pgadmin_oidc_env = var.oidc_enabled ? {
    PGADMIN_CONFIG_AUTHENTICATION_SOURCES = "['oauth2', 'internal']"
    PGADMIN_CONFIG_OAUTH2_NAME             = "'authentik'"
    PGADMIN_CONFIG_OAUTH2_DISPLAY_NAME     = "'Authentik SSO'"
    PGADMIN_CONFIG_OAUTH2_CLIENT_ID        = "'${lookup(local.oidc_data, "pgadmin_client_id", "")}'"
    PGADMIN_CONFIG_OAUTH2_CLIENT_SECRET    = "'${lookup(local.oidc_data, "pgadmin_client_secret", "")}'"
    PGADMIN_CONFIG_OAUTH2_SERVER_METADATA_URL = "'https://${local.authentik_host}/application/o/pgadmin/.well-known/openid-configuration'"
    PGADMIN_CONFIG_OAUTH2_SCOPE            = "'openid email profile'"
    PGADMIN_CONFIG_OAUTH2_AUTO_CREATE_USER = "True"
    PGADMIN_CONFIG_OAUTH2_AUTO_LOGIN       = "True"
    PGADMIN_CONFIG_MASTER_PASSWORD         = "False"
  } : {}
}

# pgAdmin UI Installation
resource "helm_release" "pgadmin" {
  name       = "pgadmin"
  repository = "https://helm.runix.net"
  chart      = "pgadmin4"
  namespace  = var.namespace
  version    = "1.23.0"

  values = [yamlencode({
    nodeSelector = {
      role = "infra"
    }
    env = {
      email    = var.pgadmin_user
      password = var.pgadmin_password
      variables = [
        for k, v in local.pgadmin_oidc_env : {
          name  = k
          value = v
        }
      ]
    }
    
    # 🔄 Automated Rollout: Checksum forces restart when OIDC config changes
    podAnnotations = {
      "checksum/config" = sha1(jsonencode(local.pgadmin_oidc_env))
    }

    # 🛠️ Persistence: Required to ensure automated settings are saved
    persistence = {
      enabled = true
      storageClass = "manual-hostpath"
      size = "1Gi"
    }

    # 🔗 Server Definition: Adds the DB to the sidebar
    serverDefinitions = {
      enabled = true
      servers = {
        PrimaryDatabase = {
          Name     = "Postgres-Primary"
          Group    = "Servers"
          Port     = 5432
          Username = var.db_user
          Host     = "postgresql"
          SSLMode  = "prefer"
          MaintenanceDB = var.db_name
        }
      }
    }

    # 🔑 Automated Login: Injecting .pgpass for passwordless entry
    # Note: pgAdmin expects the file at /var/lib/pgadmin/storage/<email_with_dots_replaced_by_underscores>/pgpass
    extraInitContainers = yamlencode([{
      name  = "setup-pgpass"
      image = "busybox"
      command = ["sh", "-c", "mkdir -p /var/lib/pgadmin/storage/${replace(var.pgadmin_user, ".", "_")} && echo 'postgresql:5432:*:${var.db_user}:${var.db_password}' > /var/lib/pgadmin/storage/${replace(var.pgadmin_user, ".", "_")}/pgpass && chmod 600 /var/lib/pgadmin/storage/${replace(var.pgadmin_user, ".", "_")}/pgpass && chown 5050:5050 /var/lib/pgadmin/storage/${replace(var.pgadmin_user, ".", "_")}/pgpass"]
      volumeMounts = [{
        name      = "pgadmin-data"
        mountPath = "/var/lib/pgadmin"
      }]
    }])
  })]

  wait = true

  lifecycle {
    prevent_destroy = true
  }
}
