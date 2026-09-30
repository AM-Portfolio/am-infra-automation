# ------------------------------------------------------------------------------
# Apache Kafka & Zookeeper & Kafka-UI (Native Helm Deployment)
# ------------------------------------------------------------------------------

# ── Data Immortality: Explicit HostPath Allocation ─────────────────────────
resource "kubernetes_persistent_volume" "kafka_pv" {
  metadata { name = "kafka-pv-immortal" }
  spec {
    capacity = { storage = var.storage }
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
  lifecycle {
    ignore_changes = [spec[0].capacity]
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
    resources { requests = { storage = var.storage } }
    volume_name = kubernetes_persistent_volume.kafka_pv.metadata[0].name
  }
  lifecycle {
    ignore_changes = [spec[0].resources]
  }
}

# ── Kafka Native Cluster (KRaft Mode) ──────────────────────────────────────
locals {
  advertised_host = var.advertised_host != "" ? var.advertised_host : (
    var.environment == "prod" ? "kafka.${var.root_domain}" : "kafka-${var.environment}.${var.root_domain}"
  )

  # Kafka-UI sidebar: local cluster is this plane; peer is the other fleet broker.
  # Contabo prod apps (Vault env=prod) → kafka.asrax.in. Dig Contabo apps share that
  # broker with *.dev. topic prefixes (store_hosts=contabo_prod). Laptop dig plane is kafka-dev.
  ui_local_name = var.ui_cluster_name != "" ? var.ui_cluster_name : (
    var.environment == "prod" ? "prod" : "dig"
  )
  ui_peer_name = var.environment == "prod" ? "dig" : "prod"
  ui_peer_bootstrap = var.environment == "prod" ? coalesce(var.ui_bootstrap_dig, "kafka-dev.asrax.in:9092") : coalesce(var.ui_bootstrap_prod, "kafka.asrax.in:9092")
  ui_preprod_bootstrap = coalesce(var.ui_bootstrap_preprod, "kafka-preprod.asrax.in:9092")
  ui_dr_bootstrap      = coalesce(var.ui_bootstrap_dr, "kafka-dr.asrax.in:9092")
}

resource "kubernetes_service" "kafka" {
  metadata {
    name      = "kafka"
    namespace = var.namespace
  }
  spec {
    selector = { app = "kafka" }
    port {
      name        = "tcp-internal"
      port        = 9092
      target_port = 9092
    }
    cluster_ip = "None" # Headless Service
  }
}

resource "kubernetes_service" "kafka_external" {
  metadata {
    name      = "kafka-external"
    namespace = var.namespace
  }
  spec {
    type     = "NodePort"
    selector = { app = "kafka" }
    port {
      name        = "tcp-external"
      port        = 29092
      target_port = 29092
      node_port   = 30092
    }
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
            value = "INTERNAL://0.0.0.0:9092,EXTERNAL://0.0.0.0:29092,CONTROLLER://0.0.0.0:9093"
          }
          env {
            name  = "KAFKA_ADVERTISED_LISTENERS"
            value = "INTERNAL://kafka:9092,EXTERNAL://${local.advertised_host}:9092"
          }
          env {
            name  = "KAFKA_LISTENER_SECURITY_PROTOCOL_MAP"
            value = "CONTROLLER:PLAINTEXT,INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT"
          }
          env {
            name  = "KAFKA_INTER_BROKER_LISTENER_NAME"
            value = "INTERNAL"
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
          port { container_port = 29092 }
          port { container_port = 9093 }
          
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/kafka/data"
          }
          resources {
            requests = { memory = var.memory_request, cpu = var.cpu_request }
            limits   = { memory = var.memory_limit, cpu = var.cpu_limit }
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
data "vault_kv_secret_v2" "oidc" {
  count = var.oidc_enabled ? 1 : 0
  mount = "secret"
  name  = "${var.environment}/infra/oidc-data-stores"
}

locals {
  oidc_data = var.oidc_enabled ? data.vault_kv_secret_v2.oidc[0].data : {}

  # Kafka OIDC Configuration (Extracted for Checksum & Reuse)
  kafka_oidc_config = {
    auth = {
      type = var.oidc_enabled ? "OAUTH2" : "DISABLED"
      oauth2 = {
        client = {
          authentik = {
            clientId               = lookup(local.oidc_data, "kafka_client_id", "")
            clientSecret           = lookup(local.oidc_data, "kafka_client_secret", "")
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

# kafka_exporter — topic / consumergroup metrics for Platform / Kafka
resource "kubernetes_deployment" "kafka_exporter" {
  metadata {
    name      = "kafka-exporter"
    namespace = var.namespace
    labels    = { app = "kafka-exporter" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "kafka-exporter" } }
    template {
      metadata {
        labels = { app = "kafka-exporter" }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "9308"
          "prometheus.io/path"   = "/metrics"
        }
      }
      spec {
        node_selector = { role = "infra" }
        container {
          name  = "kafka-exporter"
          image = "danielqsj/kafka-exporter:v1.7.0"
          args = [
            "--kafka.server=kafka.${var.namespace}.svc.cluster.local:9092",
            "--web.listen-address=:9308",
          ]
          port { container_port = 9308 }
          resources {
            requests = { memory = "32Mi", cpu = "10m" }
            limits   = { memory = "128Mi", cpu = "200m" }
          }
        }
      }
    }
  }
  depends_on = [kubernetes_stateful_set.kafka]
}

# Kafka UI Installation
resource "helm_release" "kafka_ui" {
  name       = "kafka-ui"
  repository = "https://provectus.github.io/kafka-ui-charts"
  chart      = "kafka-ui"
  namespace  = var.namespace
  version    = "0.7.5"

  # Multi-env sidebar: env vars are authoritative (yaml alone often only loads cluster[0]).
  # cluster[0] = this plane (prod Contabo or dig). cluster[1] = peer fleet broker.
  values = [yamlencode({
    envs = {
      config = {
        KAFKA_CLUSTERS_0_NAME             = local.ui_local_name
        KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS = "kafka:9092"
        KAFKA_CLUSTERS_1_NAME             = local.ui_peer_name
        KAFKA_CLUSTERS_1_BOOTSTRAPSERVERS = local.ui_peer_bootstrap
        KAFKA_CLUSTERS_2_NAME             = "preprod"
        KAFKA_CLUSTERS_2_BOOTSTRAPSERVERS = local.ui_preprod_bootstrap
        KAFKA_CLUSTERS_3_NAME             = "dr"
        KAFKA_CLUSTERS_3_BOOTSTRAPSERVERS = local.ui_dr_bootstrap
      }
    }
    yamlApplicationConfig = {
      auth = {
        type = "DISABLED"
      }
      kafka = {
        clusters = [
          { name = local.ui_local_name, bootstrapServers = "kafka:9092" },
          { name = local.ui_peer_name, bootstrapServers = local.ui_peer_bootstrap },
          { name = "preprod", bootstrapServers = local.ui_preprod_bootstrap },
          { name = "dr", bootstrapServers = local.ui_dr_bootstrap },
        ]
      }
    }

    # 🔄 Automated Rollout: Checksum forces restart when OIDC config changes
    podAnnotations = {
      "checksum/config" = sha1(jsonencode(local.kafka_oidc_config))
    }
  })]

  wait = true
}
