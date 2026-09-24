# ------------------------------------------------------------------------------
# MongoDB Gateway — Mongo Express UI
# ------------------------------------------------------------------------------

locals {
  domain_suffix = var.environment == "prod" ? "" : "-${var.environment}"
}

resource "kubectl_manifest" "ingressroute_mongodb" {
  count     = var.enable_gateway ? 1 : 0
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: mongo-express
  namespace: ${var.namespace}
spec:
  entryPoints:
    - web
    - websecure
  routes:
    - match: Host(`mongo-express${local.domain_suffix}.${var.root_domain}`)
      kind: Rule
      services:
        - name: mongo-express
          port: 8081
      middlewares:
        - name: force-https-proto
        - name: global-cors
YAML
}
