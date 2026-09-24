data "cloudflare_zone" "main" {
  count = var.manage_cloudflare ? 1 : 0
  name  = var.root_domain
}

resource "cloudflare_record" "https" {
  for_each = var.manage_cloudflare ? local.record_name : {}

  zone_id         = data.cloudflare_zone.main[0].id
  name            = each.value
  content         = local.tunnel_cname
  type            = "CNAME"
  proxied         = true
  allow_overwrite = true
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "edge" {
  count      = var.manage_cloudflare ? 1 : 0
  account_id = var.cloudflare_account_id
  tunnel_id  = var.tunnel_id

  config {
    origin_request {
      no_tls_verify = true
    }

    # Every HTTPS name → Traefik. Host rules on IngressRoutes pick the backend.
    dynamic "ingress_rule" {
      for_each = local.https_fqdn
      content {
        hostname = ingress_rule.value
        service  = local.traefik_origin

        origin_request {
          http_host_header = ingress_rule.value
          no_tls_verify    = true
        }
      }
    }

    ingress_rule {
      service = "http_status:404"
    }
  }
}
