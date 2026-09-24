# Slim Phase 2 edge: Helm Traefik + cloudflared. No Authentik / preprod routes.
# Tunnel origin is Traefik only. Host rules live on IngressRoutes.

locals {
  host_suffix = var.environment == "prod" ? "" : "-${var.environment}"
  # bare_https_names skip env suffix (shared obs hub: grafana/loki/prometheus/tempo.asrax.in)
  https_fqdn = {
    for n in var.https_names :
    n => (
      var.environment == "prod" || contains(var.bare_https_names, n)
      ? "${n}.${var.root_domain}"
      : "${n}-${var.environment}.${var.root_domain}"
    )
  }
  record_name = {
    for n in var.https_names :
    n => (
      var.environment == "prod" || contains(var.bare_https_names, n)
      ? n
      : "${n}-${var.environment}"
    )
  }
  traefik_origin = "http://traefik.${var.namespace}.svc.cluster.local:80"
  tunnel_cname   = "${var.tunnel_id}.cfargotunnel.com"
}

resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.traefik_chart_version
  namespace        = var.namespace
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    deployment = {
      replicas = 1
      podLabels = { app = "traefik" }
    }
    logs = {
      general = { level = "INFO" }
    }
    additionalArguments = [
      "--providers.kubernetescrd.allowcrossnamespace=true",
      "--api.dashboard=true",
      "--api.insecure=true",
      "--entrypoints.web.forwardedHeaders.insecure=true",
      "--entrypoints.websecure.forwardedHeaders.insecure=true",
    ]
    ports = {
      web = {
        exposedPort = 80
      }
      websecure = {
        exposedPort = 443
      }
      traefik = {
        expose = { default = true }
        port   = 8080
      }
    }
    service = {
      type = "ClusterIP"
    }
    persistence = { enabled = false }
  })]
}

resource "kubectl_manifest" "middleware_force_https_proto" {
  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: Middleware
    metadata:
      name: force-https-proto
      namespace: ${var.namespace}
    spec:
      headers:
        customRequestHeaders:
          X-Forwarded-Proto: https
  YAML

  depends_on = [helm_release.traefik]
}

resource "kubectl_manifest" "middleware_global_cors" {
  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: Middleware
    metadata:
      name: global-cors
      namespace: ${var.namespace}
    spec:
      headers:
        accessControlAllowMethods:
          - GET
          - POST
          - PUT
          - DELETE
          - OPTIONS
          - PATCH
        accessControlAllowHeaders:
          - "*"
        accessControlAllowOriginList:
          - "*"
  YAML

  depends_on = [helm_release.traefik]
}

resource "kubectl_manifest" "ingressroute_traefik_dashboard" {
  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: IngressRoute
    metadata:
      name: traefik-dashboard
      namespace: ${var.namespace}
    spec:
      entryPoints:
        - web
        - websecure
      routes:
        - match: Host(`${local.https_fqdn["traefik"]}`)
          kind: Rule
          services:
            - name: traefik
              port: 9000
  YAML

  depends_on = [helm_release.traefik]
}

resource "kubernetes_deployment_v1" "cloudflared" {
  metadata {
    name      = "cloudflared"
    namespace = var.namespace
    labels    = { app = "cloudflared" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "cloudflared" }
    }
    template {
      metadata {
        labels = { app = "cloudflared" }
      }
      spec {
        container {
          name  = "cloudflared"
          image = "cloudflare/cloudflared:2025.4.0"
          args = [
            "tunnel",
            "--no-autoupdate",
            "--metrics",
            "0.0.0.0:2000",
            "run",
            "--token",
            "$(TUNNEL_TOKEN)",
          ]
          env {
            name = "TUNNEL_TOKEN"
            value_from {
              secret_key_ref {
                name = "cloudflare-tunnel"
                key  = "token"
              }
            }
          }
          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }
          liveness_probe {
            http_get {
              path = "/ready"
              port = 2000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }
      }
    }
  }

  depends_on = [helm_release.traefik]
}
