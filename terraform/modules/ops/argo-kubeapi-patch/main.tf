# Additive Cloudflare DNS for kubeapi-* (does not own tunnel ingress).
# Tunnel origin for this hostname is merged via modules/core/edge extra_origin_ingress
# from the env edge stack — avoid a second tunnel_cloudflared_config fighting edge.

locals {
  manage_dns = var.enabled && var.manage_dns && var.tunnel_id != ""
  record_name = trimsuffix(
    replace(var.kubeapi_hostname, ".${var.root_domain}", ""),
    "."
  )
  tunnel_cname = "${var.tunnel_id}.cfargotunnel.com"
  # Refuse IP:port style Argo servers in this module
  server_ok = can(regex("^https://kubeapi-[a-z0-9.-]+\\.${replace(var.root_domain, ".", "\\.")}$", var.kubeapi_server_url))
}

resource "terraform_data" "server_url_guard" {
  count = var.enabled ? 1 : 0
  input = var.kubeapi_server_url
  lifecycle {
    precondition {
      condition     = local.server_ok
      error_message = "kubeapi_server_url must be https://kubeapi-….${var.root_domain} (no IP or nonstandard port)."
    }
  }
}

data "cloudflare_zone" "main" {
  count = local.manage_dns ? 1 : 0
  name  = var.root_domain
}

resource "cloudflare_record" "kubeapi" {
  count = local.manage_dns ? 1 : 0

  zone_id         = data.cloudflare_zone.main[0].id
  name            = local.record_name
  content         = local.tunnel_cname
  type            = "CNAME"
  proxied         = true
  allow_overwrite = true
  comment         = "argo-kubeapi-patch: Kind API hostname for Contabo Argo (additive)"
}
