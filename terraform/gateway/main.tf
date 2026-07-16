# ==============================================================================
# GATEWAY LAYER — Root Orchestrator
# ==============================================================================
# This layer handles all external connectivity, including:
#   1. Traefik Proxy (Ingress Controller)
#   2. Cloudflare DNS & Tunnel (Secure Host-to-K8s Bridge)
# ==============================================================================

# ── 1. Retrieve Secrets from Vault ───────────────────────────────────────────
# Following the "Smart Secret Resolution" strategy:
# We fetch credentials seeded in the previous 'vault' layer.
data "vault_kv_secret_v2" "gateway" {
  mount = "secret"
  name  = "${var.environment}/infra/gateway"
}

locals {
  creds = data.vault_kv_secret_v2.gateway.data
}

# ── 3. Core: Cloudflare DNS & Tunnels (Automated Mode) ──────────────────────
# Full automation of DNS and Tunnels using the verified API Token.
module "cloudflare_v2" {
  count  = local.creds["cloudflare_api_token"] != "" ? 1 : 0
  source = "./../modules/core/cloudflare"

  root_domain = var.root_domain
  environment = var.environment
  namespace   = var.infra_namespace

  cloudflare_account_id    = local.creds["cloudflare_account_id"]
  cloudflare_tunnel_secret = coalesce(var.cloudflare_tunnel_secret, lookup(local.creds, "cloudflare_tunnel_secret", ""))
  cloudflare_tunnel_id     = coalesce(var.cloudflare_tunnel_id, lookup(local.creds, "cloudflare_tunnel_id", ""))
}

# ── 4. Ingress: Traefik Proxy ─────────────────────────────────────────────────
# Deployment of the Ingress Controller and Routing rules.
module "traefik" {
  source = "./../modules/core/traefik"

  environment = var.environment
  root_domain = var.root_domain
  namespace   = var.infra_namespace
}
