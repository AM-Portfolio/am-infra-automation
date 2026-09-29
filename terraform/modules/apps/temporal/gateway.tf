locals {
  domain_suffix = var.environment == "prod" ? "" : "-${var.environment}"
  ui_host       = "temporal${local.domain_suffix}.${var.root_domain}"
}

resource "kubernetes_service_v1" "nodeport" {
  count      = var.enable_gateway ? 1 : 0
  depends_on = [helm_release.temporal]
  metadata {
    name      = "temporal-web-nodeport"
    namespace = var.namespace
    labels    = { app = "temporal-web" }
  }
  spec {
    type = "NodePort"
    selector = {
      "app.kubernetes.io/name"      = "temporal"
      "app.kubernetes.io/instance"  = "temporal"
      "app.kubernetes.io/component" = "web"
    }
    port {
      name        = "http"
      port        = 8080
      target_port = 8080
      node_port   = var.node_port
    }
  }
}

# gRPC frontend for apps via am-port-exposer :7233 (TEMPORAL_HOST=temporal-rpc-<env>.asrax.in:7233).
resource "kubernetes_service_v1" "frontend_nodeport" {
  count      = var.enable_gateway ? 1 : 0
  depends_on = [helm_release.temporal]
  metadata {
    name      = "temporal-frontend-nodeport"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"      = "temporal"
      "app.kubernetes.io/component" = "frontend"
    }
  }
  spec {
    type = "NodePort"
    selector = {
      "app.kubernetes.io/name"      = "temporal"
      "app.kubernetes.io/instance"  = "temporal"
      "app.kubernetes.io/component" = "frontend"
    }
    port {
      name        = "grpc-rpc"
      port        = 7233
      target_port = 7233
      node_port   = var.frontend_node_port
    }
  }
}

resource "kubectl_manifest" "ingressroute" {
  count     = var.enable_gateway && var.gateway_same_cluster ? 1 : 0
  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: IngressRoute
    metadata:
      name: temporal-web
      namespace: ${var.namespace}
    spec:
      entryPoints: [web, websecure]
      routes:
        - match: Host(`${local.ui_host}`)
          kind: Rule
          services:
            - name: temporal-web
              port: 8080
          middlewares:
            - name: force-https-proto
              namespace: ${var.gateway_middleware_namespace}
  YAML
}

output "node_port" { value = var.node_port }
output "frontend_node_port" { value = var.frontend_node_port }
