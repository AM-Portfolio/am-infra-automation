# Helm temporalio/temporal. Do not apply from kind-fleet/dev/stores.
# SQL stores: separate DBs `temporal` + `temporal_visibility` on postgres-<env>.asrax.in
# (Temporal schema versioning cannot share one DB name across default+visibility).
# PG role `temporal` is still provisioned on the stores stack.

resource "kubernetes_secret_v1" "db" {
  metadata {
    name      = "temporal-db-secret"
    namespace = var.namespace
  }
  data = {
    password = var.db_password
  }
}

locals {
  sql_base = {
    driver         = "postgres12"
    host           = var.db_host
    port           = 5432
    user           = var.db_user
    existingSecret = kubernetes_secret_v1.db.metadata[0].name
    secretKey      = "password"
  }
}

resource "helm_release" "temporal" {
  name             = "temporal"
  repository       = "https://temporalio.github.io/helm-charts"
  chart            = "temporal"
  namespace        = var.namespace
  version          = var.chart_version
  create_namespace = false
  wait             = true
  timeout          = 900

  values = [yamlencode({
    server = {
      replicaCount = 1
      resources = {
        requests = {
          cpu    = var.server_cpu_request
          memory = var.server_memory_request
        }
        limits = {
          cpu    = var.server_cpu_limit
          memory = var.server_memory_limit
        }
      }
      config = {
        persistence = {
          default = {
            driver = "sql"
            sql = merge(local.sql_base, {
              database = var.db_name
              maxConns = 20
            })
          }
          visibility = {
            driver = "sql"
            sql = merge(local.sql_base, {
              database = var.visibility_db_name
              maxConns = 10
            })
          }
        }
      }
      frontend = {
        service = {
          port = 7233
        }
      }
    }
    cassandra     = { enabled = false }
    mysql         = { enabled = false }
    postgresql    = { enabled = false }
    elasticsearch = { enabled = false }
    prometheus    = { enabled = false }
    grafana       = { enabled = false }
    schema = {
      createDatabase = { enabled = false }
      setup          = { enabled = true }
      update         = { enabled = true }
    }
    admintools = { enabled = true }
    web = {
      enabled      = true
      replicaCount = 1
      resources = {
        requests = {
          cpu    = var.web_cpu_request
          memory = var.web_memory_request
        }
        limits = {
          cpu    = var.web_cpu_limit
          memory = var.web_memory_limit
        }
      }
    }
  })]
}

output "ui_host" {
  value = "temporal${var.environment == "prod" ? "" : "-${var.environment}"}.${var.root_domain}"
}

output "frontend_port" {
  value = 7233
}
