# Cloudflare Load Balancing — DR (VPS3) primary, Contabo (VPS1) fallback.
# SoT for bare proxied HTTPS failover. *-dr.asrax.in stay direct to DR tunnel (edge/DR).
# No silent auto-failback: after fall-to-Contabo set dr_pool_enabled=false and apply.

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

data "cloudflare_zone" "main" {
  name = var.root_domain
}

locals {
  zone_id = data.cloudflare_zone.main.id
  domain  = var.root_domain

  prod_origin = "${var.prod_tunnel_id}.cfargotunnel.com"
  dr_origin   = "${var.dr_tunnel_id}.cfargotunnel.com"

  # Every bare hostname owned by prod edge TF (excl. obs hub on asrax-obs-tunnel).
  lb_hosts = {
    am              = { path = "/health", expected = "200", monitor = "https_health" }
    auth            = { path = "/realms/master", expected = "200", monitor = "auth_health" }
    vault           = { path = "/v1/sys/health", expected = "200,429,472,473,501,503", monitor = "vault_health" }
    argocd          = { path = "/", expected = "200,302", monitor = "https_root" }
    minio           = { path = "/", expected = "200,302,403", monitor = "https_root" }
    s3              = { path = "/", expected = "200,302,403", monitor = "https_root" }
    influx          = { path = "/", expected = "200,302", monitor = "https_root" }
    traefik         = { path = "/dashboard/", expected = "200,401", monitor = "https_root" }
    pgadmin         = { path = "/", expected = "200,302", monitor = "https_root" }
    mongo-express   = { path = "/", expected = "200,302,401", monitor = "https_root" }
    kafka-ui        = { path = "/", expected = "200,302", monitor = "https_root" }
    redis-ui        = { path = "/", expected = "200,302", monitor = "https_root" }
    temporal        = { path = "/", expected = "200,302", monitor = "https_root" }
    lago            = { path = "/", expected = "200,302", monitor = "https_root" }
    n8n             = { path = "/", expected = "200,302", monitor = "https_root" }
    growthbook      = { path = "/", expected = "200,302", monitor = "https_root" }
    openproject     = { path = "/", expected = "200,302", monitor = "https_root" }
    litellm         = { path = "/", expected = "200,302", monitor = "https_root" }
    langfuse        = { path = "/", expected = "200,302", monitor = "https_root" }
    novu            = { path = "/", expected = "200,302", monitor = "https_root" }
    corp            = { path = "/", expected = "200,302", monitor = "https_root" }
    asrax           = { path = "/", expected = "200,302", monitor = "https_root" }
  }

  # Apex shares asrax-ui; monitor like product UI.
  apex_key = "@"

  fqdn = merge(
    { for k, _ in local.lb_hosts : k => "${k}.${local.domain}" },
    { (local.apex_key) = local.domain }
  )
}

# -----------------------------------------------------------------------------
# Monitors — fail fast when DR Kind / Traefik / tunnel / VPS path is down
# -----------------------------------------------------------------------------

resource "cloudflare_load_balancer_monitor" "https_health" {
  account_id     = var.cloudflare_account_id
  type           = "https"
  description    = "AM HTTPS /health (UI/APIs) — DR-primary gate"
  method         = "GET"
  path           = "/health"
  port           = 443
  expected_codes = "200"
  interval       = var.monitor_interval
  retries        = var.monitor_retries
  timeout        = var.monitor_timeout
  consecutive_down = var.monitor_consecutive_down
  consecutive_up   = var.monitor_consecutive_up
  allow_insecure   = true
  follow_redirects = true
}

resource "cloudflare_load_balancer_monitor" "auth_health" {
  account_id     = var.cloudflare_account_id
  type           = "https"
  description    = "Keycloak realm probe (auth)"
  method         = "GET"
  path           = "/realms/master"
  port           = 443
  expected_codes = "200"
  interval       = var.monitor_interval
  retries        = var.monitor_retries
  timeout        = var.monitor_timeout
  consecutive_down = var.monitor_consecutive_down
  consecutive_up   = var.monitor_consecutive_up
  allow_insecure   = true
  follow_redirects = true
}

resource "cloudflare_load_balancer_monitor" "vault_health" {
  account_id     = var.cloudflare_account_id
  type           = "https"
  description    = "Vault sys/health"
  method         = "GET"
  path           = "/v1/sys/health"
  port           = 443
  # Vault returns 200 (active), 429 (standby), 472/473 (disaster/perform standby), 501/503 sealed/uninit.
  expected_codes = "200,429,472,473"
  interval       = var.monitor_interval
  retries        = var.monitor_retries
  timeout        = var.monitor_timeout
  consecutive_down = var.monitor_consecutive_down
  consecutive_up   = var.monitor_consecutive_up
  allow_insecure   = true
  follow_redirects = false
}

resource "cloudflare_load_balancer_monitor" "https_root" {
  account_id       = var.cloudflare_account_id
  type             = "https"
  description      = "HTTPS root probe (consoles / apex)"
  method           = "GET"
  path             = "/"
  port             = 443
  expected_codes   = "200,301,302,401,403"
  interval         = var.monitor_interval
  retries          = var.monitor_retries
  timeout          = var.monitor_timeout
  consecutive_down = var.monitor_consecutive_down
  consecutive_up   = var.monitor_consecutive_up
  allow_insecure   = true
  follow_redirects = true
}

locals {
  monitor_ids = {
    https_health = cloudflare_load_balancer_monitor.https_health.id
    https_root   = cloudflare_load_balancer_monitor.https_root.id
    auth_health  = cloudflare_load_balancer_monitor.auth_health.id
    vault_health = cloudflare_load_balancer_monitor.vault_health.id
  }
}

# -----------------------------------------------------------------------------
# Pools — one pair per hostname (Host header must match published tunnel route)
# default = DR; fallback = Contabo
# -----------------------------------------------------------------------------

resource "cloudflare_load_balancer_pool" "dr" {
  for_each = local.lb_hosts

  account_id = var.cloudflare_account_id
  name       = "am-dr-${each.key}"
  enabled    = var.dr_pool_enabled
  monitor    = local.monitor_ids[each.value.monitor]
  check_regions = ["WNAM", "ENAM", "WEU"]

  origins {
    name    = "asrax-dr-tunnel"
    address = local.dr_origin
    enabled = var.dr_pool_enabled
    weight  = 1
    header {
      header = "Host"
      values = [local.fqdn[each.key]]
    }
  }

  origin_steering {
    policy = "random"
  }

  notification_filter {
    origin {
      disable = false
      healthy = false
    }
    pool {
      disable = false
      healthy = false
    }
  }
}

resource "cloudflare_load_balancer_pool" "prod" {
  for_each = local.lb_hosts

  account_id = var.cloudflare_account_id
  name       = "am-prod-${each.key}"
  enabled    = true
  monitor    = local.monitor_ids[each.value.monitor]
  check_regions = ["WNAM", "ENAM", "WEU"]

  origins {
    name    = "asrax-prod-tunnel"
    address = local.prod_origin
    enabled = true
    weight  = 1
    header {
      header = "Host"
      values = [local.fqdn[each.key]]
    }
  }

  origin_steering {
    policy = "random"
  }
}

resource "cloudflare_load_balancer_pool" "dr_apex" {
  account_id = var.cloudflare_account_id
  name       = "am-dr-apex"
  enabled    = var.dr_pool_enabled
  monitor    = cloudflare_load_balancer_monitor.https_root.id
  check_regions = ["WNAM", "ENAM", "WEU"]

  origins {
    name    = "asrax-dr-tunnel"
    address = local.dr_origin
    enabled = var.dr_pool_enabled
    weight  = 1
    header {
      header = "Host"
      values = [local.domain]
    }
  }
}

resource "cloudflare_load_balancer_pool" "prod_apex" {
  account_id = var.cloudflare_account_id
  name       = "am-prod-apex"
  enabled    = true
  monitor    = cloudflare_load_balancer_monitor.https_root.id
  check_regions = ["WNAM", "ENAM", "WEU"]

  origins {
    name    = "asrax-prod-tunnel"
    address = local.prod_origin
    enabled = true
    weight  = 1
    header {
      header = "Host"
      values = [local.domain]
    }
  }
}

# -----------------------------------------------------------------------------
# Load balancers — steering off (failover order); fallback = Contabo
# -----------------------------------------------------------------------------

resource "cloudflare_load_balancer" "host" {
  for_each = local.lb_hosts

  zone_id          = local.zone_id
  name             = local.fqdn[each.key]
  steering_policy  = "off"
  proxied          = true
  enabled          = true
  session_affinity = "none"

  default_pool_ids = [cloudflare_load_balancer_pool.dr[each.key].id]
  fallback_pool_id = cloudflare_load_balancer_pool.prod[each.key].id

  description = "DR-primary / Contabo-fallback for ${local.fqdn[each.key]} (no auto-failback — gate via dr_pool_enabled)"
}

resource "cloudflare_load_balancer" "apex" {
  zone_id          = local.zone_id
  name             = local.domain
  steering_policy  = "off"
  proxied          = true
  enabled          = true
  session_affinity = "none"

  default_pool_ids = [cloudflare_load_balancer_pool.dr_apex.id]
  fallback_pool_id = cloudflare_load_balancer_pool.prod_apex.id

  description = "DR-primary / Contabo-fallback for apex asrax.in"
}

# -----------------------------------------------------------------------------
# Notify when DR pool becomes unhealthy (traffic on Contabo fallback)
# -----------------------------------------------------------------------------

resource "cloudflare_notification_policy" "dr_pool_unhealthy" {
  count = var.notification_email != "" ? 1 : 0

  account_id  = var.cloudflare_account_id
  name        = "am-dr-pool-unhealthy-fall-to-contabo"
  description = "DR origin/pool unhealthy → CF LB using Contabo fallback. Disable DR pool (dr_pool_enabled=false) until human restore."
  enabled     = true
  alert_type  = "load_balancing_health_alert"

  email_integration {
    id = var.notification_email
  }

  filters {
    # Unhealthy only — recovery is gated manually
    new_health   = ["Unhealthy"]
    event_source = ["pool", "origin"]
    pool_id      = [for p in cloudflare_load_balancer_pool.dr : p.id]
  }
}
