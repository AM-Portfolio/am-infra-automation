# ------------------------------------------------------------------------------
# pgAdmin Routing & Gateway
# ------------------------------------------------------------------------------

locals {
  domain_suffix = var.environment == "prod" ? "" : "-${var.environment}"
}

resource "kubectl_manifest" "ingressroute_postgres" {
  count     = var.enable_gateway ? 1 : 0
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: postgres
  namespace: ${var.namespace}
spec:
  entryPoints:
    - web
    - websecure
  routes:
    - match: Host(`pgadmin${local.domain_suffix}.${var.root_domain}`)
      kind: Rule
      services:
        - name: pgadmin-pgadmin4
          port: 80
      middlewares:
        - name: force-https-proto
        # - name: authentik-auth
YAML
}
