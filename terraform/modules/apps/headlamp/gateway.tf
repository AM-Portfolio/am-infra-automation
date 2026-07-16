# ------------------------------------------------------------------------------
# Headlamp Gateway — Traefik IngressRoute (Infrastructure Namespace)
# ------------------------------------------------------------------------------

locals {
  domain_suffix = var.environment == "local" ? "-local" : ""
}

resource "kubectl_manifest" "ingressroute_headlamp" {
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: headlamp
  namespace: ${var.namespace}
spec:
  entryPoints:
    - web
    - websecure
  routes:
    - match: Host(`headlamp${local.domain_suffix}.${var.root_domain}`)
      kind: Rule
      priority: 8000
      services:
        - name: headlamp
          port: 80
      middlewares:
        - name: force-https
        - name: force-https-proto
        - name: global-cors
YAML
}
