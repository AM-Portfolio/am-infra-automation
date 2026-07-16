# ==============================================================================
# Grafana Data Sources Integration
# ==============================================================================
# These ConfigMaps are detected by the Grafana sidecar and auto-provisioned.
# ==============================================================================

resource "kubernetes_secret" "grafana_datasources" {
  metadata {
    name      = "grafana-datasources-auto"
    namespace = var.namespace_monitoring
    labels = {
      grafana_datasource = "1"
    }
  }

  type = "Opaque"

  data = {
    "datasources.yaml" = yamlencode({
      apiVersion = 1
      datasources = [
        # 1. Prometheus
        {
          name      = "Prometheus"
          type      = "prometheus"
          access    = "proxy"
          url       = "http://prometheus-server.${var.namespace_monitoring}.svc.cluster.local:80"
          isDefault = true
          editable  = true
          jsonData  = { timeInterval = "15s" }
        },
        # 2. Loki
        {
          name     = "Loki"
          type     = "loki"
          access   = "proxy"
          url      = "http://loki-gateway.${var.namespace_monitoring}.svc.cluster.local:80"
          editable = true
          jsonData = { maxLines = 1000 }
        },
        # 3. InfluxDB (Native Flux)
        {
          name     = "InfluxDB"
          type     = "influxdb"
          access   = "proxy"
          url      = "http://influxdb-influxdb2.${var.namespace_infra}.svc.cluster.local:8086"
          editable = true
          jsonData = {
            version      = "Flux"
            organization = "am-portfolio"
            defaultBucket = "infrastructure"
            httpMode     = "POST"
          }
          secureJsonData = {
            token = var.influxdb_token
          }
        },
        # 4. PostgreSQL
        {
          name     = "PostgreSQL"
          type     = "postgres"
          access   = "proxy"
          url      = "postgresql.${var.namespace_infra}.svc.cluster.local:5432"
          user     = "postgres"
          database = "portfolio"
          editable = true
          jsonData = {
            sslmode         = "disable"
            postgresVersion = 1500
            timescaledb     = false
          }
          secureJsonData = {
            password = var.postgresql_password
          }
        }
      ]
    })
  }
}
