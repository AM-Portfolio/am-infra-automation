resource "kubernetes_service_v1" "nodeport" {
  count      = var.enable_gateway ? 1 : 0
  depends_on = [helm_release.lago]
  metadata {
    name      = "lago-front-nodeport"
    namespace = var.namespace
    labels    = { app = "lago-front" }
  }
  spec {
    type = "NodePort"
    selector = {
      "io.lago.service" = "lago-front"
    }
    port {
      name        = "http"
      port        = 80
      target_port = 80
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
      name: lago
      namespace: ${var.namespace}
    spec:
      entryPoints: [web, websecure]
      routes:
        - match: Host(`${local.ui_host}`)
          kind: Rule
          services:
            - name: lago-front-svc
              port: 80
          middlewares:
            - name: force-https-proto
              namespace: ${var.gateway_middleware_namespace}
  YAML
}

output "node_port" { value = var.node_port }
