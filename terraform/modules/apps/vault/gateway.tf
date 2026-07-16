# ------------------------------------------------------------------------------
# Vault Routing & Gateway
# ------------------------------------------------------------------------------

locals {
  domain_suffix = var.environment == "local" ? "-local" : ""
}

resource "kubectl_manifest" "ingressroute_vault" {
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
        - name: vault-ui
          port: 8200
      middlewares:
        - name: ${var.infra_namespace}-force-https-proto@kubernetescrd
        - name: ${var.infra_namespace}-vary-referer@kubernetescrd
        - name: ${var.infra_namespace}-global-cors@kubernetescrd
YAML
}
