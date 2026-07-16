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
      size         = "2Gi"
      storageClass = "standard"
    }
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
