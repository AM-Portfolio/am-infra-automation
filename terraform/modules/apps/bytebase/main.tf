# Bytebase Community — dig Contabo explore UI (IAM-3).
# Deploy into infra NS; OIDC via Keycloak client "bytebase".

variable "namespace" {
  type    = string
  default = "infra"
}

variable "environment" {
  type = string
}

variable "root_domain" {
  type    = string
  default = "asrax.in"
}

variable "issuer_url" {
  type        = string
  description = "Keycloak issuer URL"
}

variable "oidc_client_id" {
  type    = string
  default = "bytebase"
}

variable "oidc_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "pg_host" {
  type    = string
  default = "postgresql"
}

variable "pg_user" {
  type    = string
  default = "bytebase"
}

variable "pg_password" {
  type      = string
  sensitive = true
}

variable "enable_gateway" {
  type    = bool
  default = true
}

variable "node_port" {
  type    = number
  default = 0
}

locals {
  domain_suffix = var.environment == "prod" ? "" : "-${var.environment}"
  host          = "bytebase${local.domain_suffix}.${var.root_domain}"
  # Dig Contabo pilot often uses bare shared UIs; allow override via environment=prod-like bare.
  host_bare_ok  = var.environment == "dev" ? "bytebase-dev.${var.root_domain}" : local.host
}

resource "kubernetes_secret" "bytebase_pg" {
  metadata {
    name      = "bytebase-pg"
    namespace = var.namespace
  }
  data = {
    username = var.pg_user
    password = var.pg_password
  }
}

resource "kubernetes_deployment" "bytebase" {
  metadata {
    name      = "bytebase"
    namespace = var.namespace
    labels    = { app = "bytebase" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "bytebase" } }
    template {
      metadata { labels = { app = "bytebase" } }
      spec {
        container {
          name  = "bytebase"
          image = "bytebase/bytebase:latest"
          args = [
            "--data", "/var/opt/bytebase",
            "--port", "8080",
            "--external-url", "https://${local.host_bare_ok}",
          ]
          env {
            name  = "PG_URL"
            value = "postgresql://${var.pg_user}:${var.pg_password}@${var.pg_host}:5432/bytebase?sslmode=disable"
          }
          port { container_port = 8080 }
          volume_mount {
            name       = "data"
            mount_path = "/var/opt/bytebase"
          }
          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { cpu = "1", memory = "1Gi" }
          }
        }
        volume {
          name = "data"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service" "bytebase" {
  metadata {
    name      = "bytebase"
    namespace = var.namespace
  }
  spec {
    selector = { app = "bytebase" }
    port {
      name        = "http"
      port        = 80
      target_port = 8080
    }
    type = var.node_port > 0 ? "NodePort" : "ClusterIP"
    dynamic "port" {
      for_each = var.node_port > 0 ? [1] : []
      content {
        name        = "http"
        port        = 80
        target_port = 8080
        node_port   = var.node_port
      }
    }
  }
  lifecycle {
    ignore_changes = [spec]
  }
}

resource "kubernetes_service" "bytebase_np" {
  count = var.node_port > 0 ? 1 : 0
  metadata {
    name      = "bytebase-nodeport"
    namespace = var.namespace
  }
  spec {
    type     = "NodePort"
    selector = { app = "bytebase" }
    port {
      port        = 80
      target_port = 8080
      node_port   = var.node_port
    }
  }
}

resource "kubectl_manifest" "bytebase_route" {
  count = var.enable_gateway ? 1 : 0
  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: IngressRoute
    metadata:
      name: bytebase
      namespace: ${var.namespace}
    spec:
      entryPoints: [web, websecure]
      routes:
        - match: Host(`${local.host_bare_ok}`)
          kind: Rule
          services:
            - name: bytebase
              port: 80
  YAML
  depends_on = [kubernetes_service.bytebase]
}

# Built-in Bytebase MCP (/mcp) must bypass oauth2-proxy so Bearer + BB OAuth work.
# /v1/auth/login also bypasses so Cursor mcp-remote can mint a Bearer as CCOT (no browser OAuth).
resource "kubectl_manifest" "bytebase_mcp_route" {
  count = var.enable_gateway ? 1 : 0
  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: IngressRoute
    metadata:
      name: bytebase-mcp
      namespace: ${var.namespace}
    spec:
      entryPoints: [web, websecure]
      routes:
        - match: Host(`${local.host_bare_ok}`) && PathPrefix(`/mcp`)
          kind: Rule
          priority: 9500
          services:
            - name: bytebase
              port: 80
        - match: Host(`${local.host_bare_ok}`) && Path(`/v1/auth/login`)
          kind: Rule
          priority: 9500
          services:
            - name: bytebase
              port: 80
  YAML
  depends_on = [kubernetes_service.bytebase]
}

# Simple landing ConfigMap (served by a tiny nginx) with inventory placeholders.
resource "kubernetes_config_map" "data_landing" {
  metadata {
    name      = "am-data-landing"
    namespace = var.namespace
  }
  data = {
    "index.html" = <<-HTML
      <!doctype html><html><head><meta charset="utf-8"><title>AM data plane</title>
      <style>body{font-family:system-ui;margin:2rem;background:#0f1419;color:#e7ecf1}a{color:#6cb6ff}</style></head>
      <body>
      <h1>AM data plane</h1>
      <p>Explore stores (dig Contabo pilot). Counts from ConfigMap <code>db-users-inventory</code>.</p>
      <ul>
        <li><a href="https://${local.host_bare_ok}">Bytebase</a></li>
        <li><a href="https://kafka-ui.${var.root_domain}">kafka-ui</a></li>
        <li><a href="https://minio.${var.root_domain}">MinIO</a></li>
        <li><a href="https://grafana.${var.root_domain}">Grafana</a></li>
        <li><a href="${var.issuer_url}">Keycloak</a></li>
      </ul>
      </body></html>
    HTML
  }
}

resource "kubernetes_deployment" "data_landing" {
  metadata {
    name      = "am-data-landing"
    namespace = var.namespace
    labels    = { app = "am-data-landing" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "am-data-landing" } }
    template {
      metadata { labels = { app = "am-data-landing" } }
      spec {
        container {
          name  = "nginx"
          image = "nginx:1.27-alpine"
          port { container_port = 80 }
          volume_mount {
            name       = "html"
            mount_path = "/usr/share/nginx/html"
          }
        }
        volume {
          name = "html"
          config_map { name = kubernetes_config_map.data_landing.metadata[0].name }
        }
      }
    }
  }
}

resource "kubernetes_service" "data_landing" {
  metadata {
    name      = "am-data-landing"
    namespace = var.namespace
  }
  spec {
    selector = { app = "am-data-landing" }
    port {
      port        = 80
      target_port = 80
    }
  }
}

resource "kubectl_manifest" "data_landing_route" {
  count = var.enable_gateway ? 1 : 0
  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: IngressRoute
    metadata:
      name: am-data-landing
      namespace: ${var.namespace}
    spec:
      entryPoints: [web, websecure]
      routes:
        - match: Host(`data${local.domain_suffix}.${var.root_domain}`) || Host(`data.${var.root_domain}`)
          kind: Rule
          services:
            - name: am-data-landing
              port: 80
  YAML
}

output "bytebase_host" { value = local.host_bare_ok }
output "landing_hosts" {
  value = ["data${local.domain_suffix}.${var.root_domain}", "data.${var.root_domain}"]
}
