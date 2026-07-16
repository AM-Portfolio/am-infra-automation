# ------------------------------------------------------------------------------
# Rover UI Gateway — Traefik IngressRoute
# ------------------------------------------------------------------------------

locals {
  domain_suffix = var.environment == "local" ? "-local" : ""
}

resource "kubectl_manifest" "rover_ingress" {
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: rover
  namespace: ${var.namespace}
spec:
  entryPoints:
    - web
    - websecure
  routes:
    - match: Host(`rover${local.domain_suffix}.${var.root_domain}`)
      kind: Rule
      services:
        - name: rover
          port: 9000
      middlewares:
        - name: authentik-auth
          namespace: infra
  tls:
    secretName: munish-org-crt
YAML
}
