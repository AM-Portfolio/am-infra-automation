resource "kubernetes_service_v1" "nodeport" {
  count      = var.enable_gateway ? 1 : 0
  depends_on = [helm_release.langfuse]
  metadata {
    name      = "langfuse-nodeport"
    namespace = var.namespace
    labels    = { app = "langfuse" }
  }
  spec {
    type = "NodePort"
    selector = {
      "app.kubernetes.io/name" = "langfuse"
      "app"                    = "web"
    }
    port {
      name        = "http"
      port        = 3000
      target_port = 3000
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
      name: langfuse
      namespace: ${var.namespace}
    spec:
      entryPoints: [web, websecure]
      routes:
        - match: Host(`${local.ui_host}`)
          kind: Rule
          services:
            - name: langfuse-web
              port: 3000
          middlewares:
            - name: force-https-proto
              namespace: ${var.gateway_middleware_namespace}
  YAML
}

output "node_port" { value = var.node_port }
