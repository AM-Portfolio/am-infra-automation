terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
  }
}

# ==============================================================================
# CLOUDFLARE MODULE — DNS + Tunnel Routes for ALL Infrastructure Domains
# ==============================================================================

locals {
  # All infrastructure subdomains that need DNS + tunnel routing
  service_routes = {
    "authentik"    = { service = "https://traefik.infra.svc.cluster.local", port = 443 }
    "vault"        = { service = "https://traefik.infra.svc.cluster.local", port = 443 }
    "grafana"      = { service = "https://traefik.infra.svc.cluster.local", port = 443 }
    "prometheus"   = { service = "https://traefik.infra.svc.cluster.local", port = 443 }
    "influx"       = { service = "https://traefik.infra.svc.cluster.local", port = 443 }
    "kafka"        = { service = "https://traefik.infra.svc.cluster.local", port = 443 }
    "kafka-ui"     = { service = "https://traefik.infra.svc.cluster.local", port = 443 }
    "mongo"        = { service = "https://traefik.infra.svc.cluster.local", port = 443 }
    "pgadmin"      = { service = "https://traefik.infra.svc.cluster.local", port = 443 }
    "redis"        = { service = "https://traefik.infra.svc.cluster.local", port = 443 }
    "headlamp"     = { service = "https://traefik.infra.svc.cluster.local", port = 443 }
    "traefik"      = { service = "https://traefik.infra.svc.cluster.local", port = 443 }
    "rover"        = { service = "https://traefik.infra.svc.cluster.local", port = 443 }
    "minio"        = { service = "https://traefik.infra.svc.cluster.local", port = 443 }
    "s3"           = { service = "https://traefik.infra.svc.cluster.local", port = 443 }
  }
}

# ------------------------------------------------------------------------------
# 0. Zone Discovery — Automatically find the Zone ID for the root domain
# ------------------------------------------------------------------------------

data "cloudflare_zone" "main" {
  name = var.root_domain
}

# ------------------------------------------------------------------------------
# 1. Cloudflare Zero Trust Tunnel
# Strategy: If cloudflare_tunnel_id is provided, look up the existing tunnel.
#           If not, create a new one. This allows idempotent deploys.
# ------------------------------------------------------------------------------

# Create new tunnel (only when no tunnel_id is provided)
resource "cloudflare_zero_trust_tunnel_cloudflared" "new" {
  count      = var.cloudflare_tunnel_id != "" ? 0 : 1
  account_id = var.cloudflare_account_id
  name       = "am-kind-${var.environment}-tunnel"
  secret     = base64encode(coalesce(var.cloudflare_tunnel_secret, "default-secret-change-me-12345678"))

  lifecycle {
    prevent_destroy = true
  }
}

# Merge both paths into a single local for downstream use
locals {
  tunnel_id    = var.cloudflare_tunnel_id != "" ? var.cloudflare_tunnel_id : cloudflare_zero_trust_tunnel_cloudflared.new[0].id
  tunnel_cname = var.cloudflare_tunnel_id != "" ? "${var.cloudflare_tunnel_id}.cfargotunnel.com" : "${cloudflare_zero_trust_tunnel_cloudflared.new[0].id}.cfargotunnel.com"
}

# ------------------------------------------------------------------------------
# 2. DNS CNAME Records — point each subdomain to the tunnel
# ------------------------------------------------------------------------------

resource "cloudflare_record" "services" {
  for_each = local.service_routes

  zone_id = data.cloudflare_zone.main.id
  name    = "${each.key}-${var.environment}"
  content = local.tunnel_cname
  type    = "CNAME"
  proxied = true

  allow_overwrite = true

  lifecycle {
    prevent_destroy = true
  }
}

# ------------------------------------------------------------------------------
# 3. Cloudflare Tunnel Ingress Configuration (Modern Zero Trust Config)
# ------------------------------------------------------------------------------

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "modern" {
  account_id = var.cloudflare_account_id
  tunnel_id  = local.tunnel_id

  config {
    origin_request {
      no_tls_verify = true
    }

    # Route each subdomain to Traefik inside the cluster
    dynamic "ingress_rule" {
      for_each = local.service_routes
      content {
        hostname = "${ingress_rule.key}-${var.environment}.${var.root_domain}"
        service  = ingress_rule.value.service

        origin_request {
          http_host_header = "${ingress_rule.key}${var.environment == "local" ? "-local" : ""}.${var.root_domain}"
          no_tls_verify    = true
        }
      }
    }

    # Catch-all rule required by Cloudflare API
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# ------------------------------------------------------------------------------
# 4. Deploy cloudflared Daemon as a Kubernetes Deployment
# ------------------------------------------------------------------------------

resource "kubernetes_secret" "cloudflare_tunnel_creds" {
  metadata {
    name      = "cloudflare-tunnel-credentials"
    namespace = var.namespace
  }

  type = "Opaque"

  data = {
    "credentials.json" = jsonencode({
      AccountTag   = var.cloudflare_account_id
      TunnelSecret = base64encode(coalesce(var.cloudflare_tunnel_secret, "default-secret-change-me-12345678"))
      TunnelID     = local.tunnel_id
    })
  }
}

resource "kubernetes_config_map" "cloudflared_config" {
  metadata {
    name      = "cloudflared-config"
    namespace = var.namespace
  }

  data = {
    "config.yaml" = yamlencode({
      tunnel           = local.tunnel_id
      credentials-file = "/etc/cloudflared/credentials.json"
      ingress = concat(
        [
          for subdomain, cfg in local.service_routes : {
            hostname = "${subdomain}-${var.environment}.${var.root_domain}"
            service  = cfg.service
            originRequest = {
              httpHostHeader = "${subdomain}${var.environment == "local" ? "-local" : ""}.${var.root_domain}"
              noTLSVerify    = true
              # Force standard HTTPS port in all forwarded headers to prevent port injection
              customRequestHeaders = {
                "X-Forwarded-Port" = "443"
              }
            }
          }
        ],
        [{ service = "http_status:404" }]
      )
    })
  }
}

resource "kubernetes_deployment" "cloudflared" {
  metadata {
    name      = "cloudflared"
    namespace = var.namespace
    labels = {
      app = "cloudflared"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "cloudflared"
      }
    }

    template {
      metadata {
        labels = {
          app = "cloudflared"
        }
      }

      spec {
        container {
          name  = "cloudflared"
          image = "cloudflare/cloudflared:latest"
          args  = ["tunnel", "--config", "/etc/cloudflared/config.yaml", "run"]

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/cloudflared/config.yaml"
            sub_path   = "config.yaml"
          }

          volume_mount {
            name       = "credentials"
            mount_path = "/etc/cloudflared/credentials.json"
            sub_path   = "credentials.json"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.cloudflared_config.metadata[0].name
          }
        }

        volume {
          name = "credentials"
          secret {
            secret_name = kubernetes_secret.cloudflare_tunnel_creds.metadata[0].name
          }
        }
      }
    }
  }
}
