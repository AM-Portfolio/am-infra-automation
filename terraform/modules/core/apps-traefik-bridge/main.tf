# Bridge apps-cluster Traefik (NodePort) into infra Traefik for product UI hosts.
# Multi-host IngressRoute → Service/Endpoints pointing at apps Kind CP NodePort.

terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20.0"
    }
  }
}

data "external" "backend_ip" {
  count = var.backend_host != "" && var.backend_ip == "" ? 1 : 0
  program = ["bash", "-c", <<-BASH
    set -euo pipefail
    NAME="${var.backend_host}"
    IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NAME" 2>/dev/null | head -1)
    if [ -z "$IP" ]; then echo "docker inspect failed for $NAME" >&2; exit 1; fi
    printf '{"ip":"%s"}\n' "$IP"
  BASH
  ]
}

module "contracts" {
  source     = "../kind-fleet-contracts"
  host_fqdns = var.host_fqdns
}

locals {
  resolved_ip = var.backend_ip != "" ? var.backend_ip : (
    var.backend_host != "" ? data.external.backend_ip[0].result.ip : ""
  )
  host_match = module.contracts.host_match
}

resource "terraform_data" "backend_ip_required" {
  input = local.resolved_ip
  lifecycle {
    precondition {
      condition     = local.resolved_ip != ""
      error_message = "apps-traefik-bridge: set backend_ip or backend_host."
    }
    precondition {
      condition     = length(var.host_fqdns) > 0
      error_message = "apps-traefik-bridge: host_fqdns must be non-empty."
    }
  }
}

resource "kubernetes_service_v1" "bridge" {
  metadata {
    name      = var.service_name
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name" = var.service_name
      "am.io/bridge"           = "cross-cluster"
      "am.io/backend-host"     = var.backend_host != "" ? var.backend_host : "static-ip"
    }
  }
  spec {
    port {
      name        = "http"
      port        = var.service_port
      target_port = var.backend_port
      protocol    = "TCP"
    }
  }

  depends_on = [terraform_data.backend_ip_required]
}

resource "kubernetes_endpoints_v1" "bridge" {
  metadata {
    name      = var.service_name
    namespace = var.namespace
    labels = {
      "am.io/bridge"       = "cross-cluster"
      "am.io/backend-host" = var.backend_host != "" ? var.backend_host : "static-ip"
    }
  }
  subset {
    address {
      ip = local.resolved_ip
    }
    port {
      name     = "http"
      port     = var.backend_port
      protocol = "TCP"
    }
  }

  depends_on = [terraform_data.backend_ip_required]
}

resource "kubectl_manifest" "ingressroute" {
  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: IngressRoute
    metadata:
      name: ${var.service_name}
      namespace: ${var.namespace}
    spec:
      entryPoints:
        - web
        - websecure
      routes:
        - match: ${local.host_match}
          kind: Rule
          services:
            - name: ${var.service_name}
              port: ${var.service_port}
          middlewares:
            - name: ${var.middleware_name}
  YAML

  depends_on = [kubernetes_service_v1.bridge, kubernetes_endpoints_v1.bridge]
}

output "host_fqdns" { value = var.host_fqdns }
output "backend_ip" { value = local.resolved_ip }
output "host_match" { value = local.host_match }
