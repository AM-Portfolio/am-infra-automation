# ------------------------------------------------------------------------------
# Kafka UI Routing & Gateway
# ------------------------------------------------------------------------------

locals {
  domain_suffix = var.environment == "prod" ? "" : "-${var.environment}"
}

resource "kubectl_manifest" "ingressroute_kafka" {
  count     = var.enable_gateway ? 1 : 0
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: kafka-ui
  namespace: ${var.namespace}
spec:
  entryPoints:
    - web
    - websecure
  routes:
    - match: Host(`kafka-ui${local.domain_suffix}.${var.root_domain}`)
      kind: Rule
      services:
        - name: kafka-ui
          port: 80
      middlewares:
        - name: force-https-proto
        - name: global-cors
YAML
}
