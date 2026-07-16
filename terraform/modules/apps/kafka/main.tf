# ------------------------------------------------------------------------------
# Apache Kafka & Zookeeper & Kafka-UI (Native Helm Deployment)
# ------------------------------------------------------------------------------

# ── Data Immortality: Explicit HostPath Allocation ─────────────────────────
resource "kubernetes_persistent_volume" "kafka_pv" {
  metadata { name = "kafka-pv-immortal" }
  spec {
    capacity = { storage = "5Gi" }
    volume_mode                      = "Filesystem"
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "manual-hostpath"
    persistent_volume_source {
      host_path {
        path = "/var/am-infra/data/kafka"
        type = "DirectoryOrCreate"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "kafka_pvc" {
  metadata {
    name      = "kafka-pvc-immortal"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "manual-hostpath"
    resources { requests = { storage = "5Gi" } }
    volume_name = kubernetes_persistent_volume.kafka_pv.metadata[0].name
  }
}

# ── Kafka Native Cluster (KRaft Mode) ──────────────────────────────────────
resource "kubernetes_service" "kafka" {
  metadata {
    name      = "kafka"
    namespace = var.namespace
  }
  spec {
    selector = { app = "kafka" }
    port {
      name        = "tcp-client"
      port        = 9092
      target_port = 9092
    }
    cluster_ip = "None" # Headless Service
  }
}

resource "kubernetes_stateful_set" "kafka" {
  metadata {
    name      = "kafka"
    namespace = var.namespace
    labels    = { app = "kafka" }
  }
  spec {
    service_name = "kafka"
    replicas     = 1
    selector { match_labels = { app = "kafka" } }
    template {
      metadata { labels = { app = "kafka" } }
      spec {
        security_context {
          fs_group = 1000
        }
        init_container {
          name  = "fix-permissions"
          image = "busybox"
          command = ["sh", "-c", "chown -R 1000:1000 /var/lib/kafka/data"]
          security_context {
            run_as_user = 0
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/kafka/data"
          }
        }
        container {
          name  = "kafka"
          image = "confluentinc/cp-kafka:7.6.0"
          
          # Native Confluent KRaft Environment Variables
          env {
            name  = "KAFKA_NODE_ID"
            value = "1"
          }
          env {
            name  = "KAFKA_PROCESS_ROLES"
            value = "broker,controller"
          }
          env {
            name  = "KAFKA_LISTENERS"
            value = "PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093"
          }
          env {
            name  = "KAFKA_ADVERTISED_LISTENERS"
            value = "PLAINTEXT://kafka:9092"
          }
          env {
            name  = "KAFKA_LISTENER_SECURITY_PROTOCOL_MAP"
            value = "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT"
          }
          env {
            name  = "KAFKA_CONTROLLER_QUORUM_VOTERS"
            value = "1@localhost:9093"
          }
          env {
            name  = "KAFKA_CONTROLLER_LISTENER_NAMES"
            value = "CONTROLLER"
          }
          env {
            name  = "KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR"
            value = "1"
          }
          env {
            name  = "KAFKA_TRANSACTION_STATE_LOG_MIN_ISR"
            value = "1"
          }
          env {
            name  = "KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR"
            value = "1"
          }
          env {
            name  = "KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS"
            value = "0"
          }
          env {
            name  = "CLUSTER_ID"
            value = "MkU3OEVBNTcwNTJENDM2Qk"
          }
          
          # Ensure persistent path is explicitly passed to Kafka
          env {
            name  = "KAFKA_LOG_DIRS"
            value = "/var/lib/kafka/data/kraft-combined-logs"
          }
          
          port { container_port = 9092 }
          port { container_port = 9093 }
          
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/kafka/data"
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.kafka_pvc.metadata[0].name
          }
        }
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ------------------------------------------------------------------------------
# OIDC Configuration Fetch (from Vault)
# ------------------------------------------------------------------------------
data "vault_generic_secret" "oidc" {
  path = "secret/infra/oidc-data-stores"
}

locals {
  oidc_data = data.vault_generic_secret.oidc.data

  # Kafka OIDC Configuration (Extracted for Checksum & Reuse)
  kafka_oidc_config = {
    auth = {
      type = "OAUTH2"
      oauth2 = {
        client = {
          authentik = {
            clientId               = local.oidc_data["kafka_client_id"]
            clientSecret           = local.oidc_data["kafka_client_secret"]
            scope                  = ["openid", "profile", "email"]
            redirectUri            = "https://kafka-local.munish.org/login/oauth2/code/authentik"
            issuerUri              = "http://authentik-server.identity.svc.cluster.local/application/o/authentik/"
            clientName             = "Authentik SSO"
            provider               = "authentik"
            authorizationGrantType = "authorization_code"
          }
        }
      }
    }
  }
}

# Kafka UI Installation
resource "helm_release" "kafka_ui" {
  name       = "kafka-ui"
  repository = "https://provectus.github.io/kafka-ui-charts"
  chart      = "kafka-ui"
  namespace  = var.namespace
  version    = "0.7.5"

  values = [yamlencode({
    yamlApplicationConfig = {
      kafka = {
        clusters = [
          {
            name             = "local"
            bootstrapServers = "kafka:9092"
          }
        ]
      }
      auth = {
        type = "DISABLED"
      }
    }

    # 🔄 Automated Rollout: Checksum forces restart when OIDC config changes
    podAnnotations = {
      "checksum/config" = sha1(jsonencode(local.kafka_oidc_config))
    }
  })]

  wait = true
}
