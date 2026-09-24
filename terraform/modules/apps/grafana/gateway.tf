# ------------------------------------------------------------------------------
# Grafana Routing & Gateway (same-cluster Traefik only)
# ------------------------------------------------------------------------------

resource "kubectl_manifest" "ingressroute_grafana" {
  count = var.enable_gateway ? 1 : 0

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
YAML

  depends_on = [helm_release.grafana]
}
