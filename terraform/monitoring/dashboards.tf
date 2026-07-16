# ==============================================================================
# Grafana Dashboards Integration
# ==============================================================================
# These ConfigMaps are detected by the Grafana sidecar and auto-imported.
# ==============================================================================

resource "kubernetes_config_map" "dashboard_preprod_logs" {
  metadata {
    name      = "grafana-dashboard-preprod-logs"
    namespace = var.namespace_monitoring
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "preprod-logs.json" = jsonencode({
      "annotations" = { "list" = [] }
      "editable"    = true
      "fiscalYearStartMonth" = 0
      "graphTooltip" = 0
      "id"           = null
      "links"        = []
      "liveNow"      = false
      "panels"       = [
        {
          "datasource" = { "type" = "loki", "uid" = "loki" }
          "gridPos"    = { "h" = 12, "w" = 24, "x" = 0, "y" = 0 }
          "id"         = 1
          "options"    = {
            "dedupStrategy"      = "none"
            "enableLogDetails"   = true
            "prettifyLogMessage" = false
            "showCommonLabels"   = false
            "showLabels"         = false
            "showTime"           = true
            "sortOrder"          = "Descending"
            "wrapLogMessage"     = true
          }
          "targets" = [
            {
              "datasource" = { "type" = "loki", "uid" = "loki" }
              "editorMode"  = "code"
              "expr"        = "{namespace=~\"$namespace\"}"
              "queryType"   = "range"
              "refId"       = "A"
            }
          ]
          "title" = "Pod Logs"
          "type"  = "logs"
        }
      ]
      "refresh"       = "5s"
      "schemaVersion" = 38
      "style"         = "dark"
      "tags"          = ["logs"]
      "templating"    = {
        "list" = [
          {
            "datasource" = { "type" = "loki", "uid" = "loki" }
            "definition" = "label_values(namespace)"
            "hide"       = 0
            "includeAll" = true
            "label"      = "Namespace"
            "multi"      = true
            "name"       = "namespace"
            "query"      = "label_values(namespace)"
            "refresh"    = 1
            "type"       = "query"
          }
        ]
      }
      "time"          = { "from" = "now-1h", "to" = "now" }
      "timepicker"    = {}
      "timezone"      = ""
      "title"         = "Cluster Pod Logs"
      "uid"           = "am-cluster-logs"
      "version"       = 2
    })
  }
}
