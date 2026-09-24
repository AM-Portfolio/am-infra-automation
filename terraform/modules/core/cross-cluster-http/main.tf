# Bridge a NodePort on another Kind cluster into Traefik on this cluster.
# Creates Service (no selector) + Endpoints + IngressRoute.

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

# Resolve Kind node IP via Docker DNS at every apply when backend_host is set.
# Endpoints cannot store hostnames — only IPs — so post-restart must re-apply or
# run kind-fleet/*/obs/scripts/refresh-platform-bridges.ps1.
data "external" "backend_ip" {
  count = var.backend_host != "" && var.backend_ip == "" ? 1 : 0
  program = ["PowerShell", "-NoProfile", "-Command", <<-PS
    $ErrorActionPreference = 'Stop'
    $hostName = '${var.backend_host}'
    $ip = docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $hostName 2>$null
    if (-not $ip) { throw "$hostName not found (is Kind up?)" }
    @{ ip = $ip.Trim() } | ConvertTo-Json -Compress
  PS
  ]
}

locals {
  domain_suffix = var.use_bare_fqdn || var.environment == "prod" ? "" : "-${var.environment}"
  fqdn          = "${var.host_label}${local.domain_suffix}.${var.root_domain}"
  resolved_ip   = var.backend_ip != "" ? var.backend_ip : (
    var.backend_host != "" ? data.external.backend_ip[0].result.ip : ""
  )
}

resource "terraform_data" "backend_ip_required" {
  input = local.resolved_ip
  lifecycle {
    precondition {
      condition     = local.resolved_ip != ""
      error_message = "cross-cluster-http: set backend_ip or backend_host (Docker DNS name)."
    }
  }
}

resource "kubernetes_service_v1" "ext" {
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

resource "kubernetes_endpoints_v1" "ext" {
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
        - match: Host(`${local.fqdn}`)
          kind: Rule
          services:
            - name: ${var.service_name}
              port: ${var.service_port}
          middlewares:
            - name: force-https-proto
  YAML

  depends_on = [kubernetes_service_v1.ext, kubernetes_endpoints_v1.ext]
}

output "fqdn" {
  value = local.fqdn
}
