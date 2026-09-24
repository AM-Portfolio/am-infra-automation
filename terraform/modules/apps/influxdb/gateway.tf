# ------------------------------------------------------------------------------
# InfluxDB Routing & Gateway
# ------------------------------------------------------------------------------

locals {
  domain_suffix = var.environment == "prod" ? "" : "-${var.environment}"
}

resource "kubectl_manifest" "ingressroute_influxdb" {
  count     = var.enable_gateway ? 1 : 0
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: influxdb
  namespace: ${var.namespace}
spec:
  entryPoints:
    - web
    - websecure
  routes:
    - match: Host(`influx${local.domain_suffix}.${var.root_domain}`)
      kind: Rule
      services:
        - name: influxdb-influxdb2
          port: 80
      middlewares:
        - name: force-https-proto
        - name: global-cors
        - name: influxdb-token-injection
YAML
}

resource "kubectl_manifest" "middleware_influxdb_token" {
  count     = var.enable_gateway ? 1 : 0
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: influxdb-token-injection
  namespace: ${var.namespace}
spec:
  headers:
    customRequestHeaders:
      Authorization: "Token ${var.influx_token}"
YAML
}
