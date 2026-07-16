# ------------------------------------------------------------------------------
# Grafana + Prometheus + Loki + Promtail (Observability Stack)
# ------------------------------------------------------------------------------

locals {
  domain_suffix = var.environment == "local" ? "-local" : ""
  # Grafana OIDC Configuration (Extracted for Checksum & Reuse)
  grafana_oidc_config = {
    GF_AUTH_GENERIC_OAUTH_ENABLED         = "true"
    GF_AUTH_GENERIC_OAUTH_NAME            = "Authentik"
    GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP   = "true"
    GF_AUTH_GENERIC_OAUTH_CLIENT_ID       = var.grafana_client_id
    GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET   = var.grafana_client_secret
    GF_AUTH_GENERIC_OAUTH_AUTH_URL        = "${trimsuffix(var.issuer_url, "/")}/authorize/"
    GF_AUTH_GENERIC_OAUTH_TOKEN_URL       = "${trimsuffix(var.issuer_url, "/")}/token/"
    GF_AUTH_GENERIC_OAUTH_API_URL         = "${trimsuffix(var.issuer_url, "/")}/userinfo/"
    GF_AUTH_GENERIC_OAUTH_SCOPES          = "openid profile email"
    GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH = "'Admin'" # 🔓 Everyone is Admin in local env
    GF_AUTH_GENERIC_OAUTH_AUTO_LOGIN       = "true" # 🚀 Zero-Click
    GF_USERS_VIEWERS_CAN_EXPLORE          = "true" # 🔭 Fallback for exploration
  }
}

# 1. GRAFANA (Dashboard)
resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = var.namespace
  version    = "7.0.0"

  values = [yamlencode({
    adminUser     = var.grafana_admin_user
    adminPassword = var.grafana_admin_password
    
    rbac = { namespaced = true }

    env = merge({
      GF_SERVER_ROOT_URL                    = "https://grafana${local.domain_suffix}.${var.root_domain}"
      GF_SERVER_SERVE_FROM_SUB_PATH         = "false"
    }, local.grafana_oidc_config)

    # 🔄 Automated Rollout: Checksum forces restart when OIDC config changes
    podAnnotations = {
      "checksum/config" = sha1(jsonencode(local.grafana_oidc_config))
    }

    sidecar = {
      dashboards  = { enabled = true, label = "grafana_dashboard", folder = "/var/lib/grafana/dashboards" }
      datasources = { enabled = true, label = "grafana_datasource" }
    }

    persistence = { enabled = true, size = "2Gi", storageClass = "standard" }
    annotations = { "helm.sh/resource-policy" = "keep" }
  })]

  wait = true
  lifecycle { prevent_destroy = true }
}

# 2. PROMETHEUS (Metrics Scraper)
resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  namespace  = var.namespace
  version    = "25.1.0"

  values = [yamlencode({
    alertmanager = { enabled = false }
    pushgateway  = { enabled = false }
    server = {
      global = { scrape_interval = "15s" }
      persistence = { enabled = true, size = "5Gi", storageClass = "standard" }
    }
  })]

  wait = true

  lifecycle {
    prevent_destroy = true
  }
}

# 3. LOKI (Log Aggregation Database)
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  namespace  = var.namespace
  version    = "5.36.0"

  values = [yamlencode({
    loki = {
      auth_enabled = false
      commonConfig = { replication_factor = 1 }
      storage      = { type = "filesystem" }
      limits_config = {
        ingestion_rate_mb       = 10
        ingestion_burst_size_mb = 20
        max_streams_per_user    = 10000
      }
    }
    singleBinary = { replicas = 1 }
  })]

  wait = true

  lifecycle {
    prevent_destroy = true
  }
}

# 4. PROMTAIL (Node Log Shipper)
resource "helm_release" "promtail" {
  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  namespace  = var.namespace
  version    = "6.15.5"

  values = [yamlencode({
    config = {
      clients = [
        { url = "http://loki-gateway.${var.namespace}.svc.cluster.local/loki/api/v1/push" }
      ]
    }
  })]

  wait = true
}
