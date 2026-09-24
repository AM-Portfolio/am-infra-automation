resource "kubernetes_service_v1" "nodeport" {
  count      = var.enable_gateway ? 1 : 0
  depends_on = [helm_release.novu]
  metadata {
    name      = "novu-web-nodeport"
    namespace = var.namespace
    labels    = { app = "novu", component = "web" }
  }
  spec {
    type = "NodePort"
    selector = {
      app       = "novu"
      component = "web"
    }
    port {
      name        = "http"
      port        = 4200
      target_port = 4200
      node_port   = var.node_port
    }
  }
}

resource "kubectl_manifest" "ingressroute" {
  count     = var.enable_gateway && var.gateway_same_cluster ? 1 : 0
  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: IngressRoute
    metadata:
      name: novu
      namespace: ${var.namespace}
    spec:
      entryPoints: [web, websecure]
      routes:
        - match: Host(`${local.ui_host}`)
          kind: Rule
          services:
            - name: novu-web
              port: 4200
          middlewares:
            - name: force-https-proto
              namespace: ${var.gateway_middleware_namespace}
  YAML
}

output "node_port" { value = var.node_port }
