# ------------------------------------------------------------------------------
# InfluxDB (Native Helm Deployment)
# ------------------------------------------------------------------------------

resource "helm_release" "influxdb" {
  name       = "influxdb"
  repository = "https://helm.influxdata.com/"
  chart      = "influxdb2"
  namespace  = var.namespace
  version    = "2.1.2"

  values = [yamlencode({
    adminUser = {
      user     = var.influx_user
      password = var.influx_password
      token    = var.influx_token
    }
    persistence = {
      enabled      = true
      size         = var.storage
      storageClass = "standard"
    }
    resources = {
      requests = {
        cpu    = var.cpu_request
        memory = var.memory_request
      }
      limits = {
        cpu    = var.cpu_limit
        memory = var.memory_limit
      }
    }
    service = {
      type     = "NodePort"
      port     = 80
      nodePort = 30806
    }
    env = [
      { name = "INFLUXD_STORAGE_CACHE_MAX_MEMORY_SIZE", value = "536870912" }
    ]
    # ENTERPRISE PREVENTION LOCK: Do NOT delete the Influx DB accidentally
    annotations = {
      "helm.sh/resource-policy" = "keep"
    }
  })]

  wait = true

  lifecycle {
    prevent_destroy = true
  }
}
