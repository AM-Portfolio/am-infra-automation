locals {
  domain_suffix = var.environment == "prod" ? "" : "-${var.environment}"
}

resource "kubectl_manifest" "ingressroute_vault" {
  count     = var.enable_gateway ? 1 : 0
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: vault
  namespace: ${var.namespace}
spec:
  entryPoints:
    - web
    - websecure
  routes:
    - match: Host(`vault${local.domain_suffix}.${var.root_domain}`)
      kind: Rule
      services:
        - name: vault
          port: 8200
YAML
}
