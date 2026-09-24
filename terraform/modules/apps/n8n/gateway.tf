# Fleet: Traefik on infra — leave gateway_same_cluster=false; use modules/core/cross-cluster-http.

resource "kubernetes_service_v1" "nodeport" {
  count      = var.enable_gateway ? 1 : 0
  depends_on = [helm_release.n8n]
  metadata {
    name      = "n8n-nodeport"
    namespace = var.namespace
    labels    = { app = "n8n" }
  }
  spec {
    type = "NodePort"
    selector = {
      "app.kubernetes.io/name"     = "n8n"
      "app.kubernetes.io/instance" = "n8n"
    }
    port {
      name        = "http"
      port        = 5678
      target_port = 5678
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
      name: n8n
      namespace: ${var.namespace}
    spec:
      entryPoints: [web, websecure]
      routes:
        - match: Host(`${local.ui_host}`)
          kind: Rule
          services:
            - name: n8n
              port: 5678
          middlewares:
            - name: force-https-proto
              namespace: ${var.gateway_middleware_namespace}
  YAML
}

output "node_port" { value = var.node_port }
