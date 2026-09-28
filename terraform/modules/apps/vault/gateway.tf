locals {
  domain_suffix = var.environment == "prod" ? "" : "-${var.environment}"
  vault_fqdn    = "vault${local.domain_suffix}.${var.root_domain}"
  vault_bare    = "vault.${var.root_domain}"
  host_match = (
    var.also_match_bare && local.vault_fqdn != local.vault_bare
    ? "Host(`${local.vault_fqdn}`) || Host(`${local.vault_bare}`)"
    : "Host(`${local.vault_fqdn}`)"
  )
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
    - match: ${local.host_match}
      kind: Rule
      services:
        - name: vault
          port: 8200
YAML
}
