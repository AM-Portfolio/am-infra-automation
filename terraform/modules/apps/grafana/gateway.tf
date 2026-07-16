# ------------------------------------------------------------------------------
# Grafana Routing & Gateway
# ------------------------------------------------------------------------------

resource "kubectl_manifest" "ingressroute_grafana" {
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: grafana
  namespace: ${var.namespace}
spec:
  entryPoints:
    - web
    - websecure
  routes:
    - match: Host(`grafana${local.domain_suffix}.${var.root_domain}`)
      kind: Rule
      services:
        - name: grafana
          port: 80
      middlewares:
        - name: ${var.infra_namespace}-force-https-proto@kubernetescrd
        - name: ${var.infra_namespace}-vary-referer@kubernetescrd
        - name: ${var.infra_namespace}-global-cors@kubernetescrd
YAML
}
