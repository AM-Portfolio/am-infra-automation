# ------------------------------------------------------------------------------
# Grafana + Prometheus + Loki (Observability Stack)
# Fleet Kind: set enable_node_selector=false, enable_promtail=false, enable_gateway=false
# (cross-cluster-http bridges grafana/loki). OIDC: oidc_provider=keycloak|authentik|none
# ------------------------------------------------------------------------------

locals {
  domain_suffix = var.use_bare_fqdn || var.environment == "prod" ? "" : "-${var.environment}"
  grafana_host  = "grafana${local.domain_suffix}.${var.root_domain}"

  node_selector = var.enable_node_selector ? { role = "observability" } : {}

  keycloak_oidc = {
    GF_AUTH_GENERIC_OAUTH_ENABLED               = "true"
    GF_AUTH_GENERIC_OAUTH_NAME                  = "Keycloak"
    GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP         = "true"
    GF_AUTH_GENERIC_OAUTH_CLIENT_ID             = var.grafana_client_id
    GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET         = var.grafana_client_secret
    GF_AUTH_GENERIC_OAUTH_SCOPES                = "openid profile email"
    GF_AUTH_GENERIC_OAUTH_AUTH_URL              = "${trimsuffix(var.issuer_url, "/")}/protocol/openid-connect/auth"
    GF_AUTH_GENERIC_OAUTH_TOKEN_URL             = "${trimsuffix(var.issuer_url, "/")}/protocol/openid-connect/token"
    GF_AUTH_GENERIC_OAUTH_API_URL               = "${trimsuffix(var.issuer_url, "/")}/protocol/openid-connect/userinfo"
    GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH   = "contains(roles[*], 'admin') && 'Admin' || contains(roles[*], 'am-admin') && 'Admin' || contains(roles[*], 'ops') && 'Editor' || contains(roles[*], 'am-ops') && 'Editor' || contains(roles[*], 'viewer') && 'Viewer' || contains(roles[*], 'am-viewer') && 'Viewer' || 'Viewer'"
    GF_AUTH_GENERIC_OAUTH_AUTO_LOGIN            = "false"
    GF_USERS_VIEWERS_CAN_EXPLORE                = "true"
    GF_AUTH_DISABLE_LOGIN_FORM                  = var.disable_login_form ? "true" : "false"
    GF_AUTH_BASIC_ENABLED                       = var.disable_login_form ? "false" : "true"
  }

  authentik_oidc = {
    GF_AUTH_GENERIC_OAUTH_ENABLED             = "true"
    GF_AUTH_GENERIC_OAUTH_NAME                = "Authentik"
    GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP       = "true"
    GF_AUTH_GENERIC_OAUTH_CLIENT_ID           = var.grafana_client_id
    GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET       = var.grafana_client_secret
    GF_AUTH_GENERIC_OAUTH_AUTH_URL            = "${trimsuffix(var.issuer_url, "/")}/authorize/"
    GF_AUTH_GENERIC_OAUTH_TOKEN_URL           = "${trimsuffix(var.issuer_url, "/")}/token/"
    GF_AUTH_GENERIC_OAUTH_API_URL             = "${trimsuffix(var.issuer_url, "/")}/userinfo/"
    GF_AUTH_GENERIC_OAUTH_SCOPES              = "openid profile email"
    GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH = "'Admin'"
    GF_AUTH_GENERIC_OAUTH_AUTO_LOGIN         = "true"
    GF_USERS_VIEWERS_CAN_EXPLORE              = "true"
  }

  grafana_oidc_config = (
    var.oidc_provider == "keycloak" ? local.keycloak_oidc :
    var.oidc_provider == "authentik" ? local.authentik_oidc :
    {}
  )
}

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = var.namespace
  version    = var.grafana_chart_version
  create_namespace = true

  values = [yamlencode({
    nodeSelector  = local.node_selector
    adminUser     = var.grafana_admin_user
    adminPassword = var.grafana_admin_password

    service = merge(
      {
        type = var.grafana_service_type
        port = 80
      },
      var.grafana_node_port > 0 ? { nodePort = var.grafana_node_port } : {}
    )

    env = merge({
      GF_SERVER_ROOT_URL            = "https://${local.grafana_host}"
      GF_SERVER_SERVE_FROM_SUB_PATH = "false"
      GF_AUTH_ANONYMOUS_ENABLED     = "false"
    }, local.grafana_oidc_config)

    podAnnotations = length(local.grafana_oidc_config) > 0 ? {
      "checksum/oidc" = sha1(jsonencode(local.grafana_oidc_config))
    } : {}

    sidecar = {
      dashboards  = { enabled = true, label = "grafana_dashboard", folder = "/var/lib/grafana/dashboards" }
      datasources = { enabled = true, label = "grafana_datasource" }
    }

    persistence = {
      enabled          = var.enable_persistence
      size             = "2Gi"
      storageClassName = var.storage_class
    }

    resources = var.grafana_resources
  })]

  wait    = true
  timeout = 600

  lifecycle {
    prevent_destroy = false
  }
}

resource "helm_release" "prometheus" {
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus"
  namespace        = var.namespace
  version          = var.prometheus_chart_version
  create_namespace = true

  values = [yamlencode({
    alertmanager = { enabled = false }
    pushgateway  = { enabled = false }
    server = {
      nodeSelector = local.node_selector
      global       = { scrape_interval = "15s" }
      # Alloy cross-cluster remote_write (HTTPS via Traefik → this NodePort)
      extraFlags = [
        "web.enable-lifecycle",
        "web.enable-remote-write-receiver",
      ]
      persistentVolume = {
        enabled      = var.enable_persistence
        size         = "5Gi"
        storageClass = var.storage_class
      }
      service = merge(
        { type = var.prometheus_service_type },
        var.prometheus_node_port > 0 ? { nodePort = var.prometheus_node_port } : {}
      )
    }
  })]

  wait    = true
  timeout = 600
}

resource "helm_release" "loki" {
  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  namespace        = var.namespace
  version          = var.loki_chart_version
  create_namespace = true

  values = [yamlencode({
    deploymentMode = "SingleBinary"
    loki = {
      auth_enabled  = false
      commonConfig  = { replication_factor = 1 }
      storage       = { type = "filesystem" }
      limits_config = {
        ingestion_rate_mb         = 10
        ingestion_burst_size_mb   = 20
        max_streams_per_user      = 10000
        allow_structured_metadata = false
      }
      schemaConfig = {
        configs = [{
          from         = "2024-01-01"
          store        = "tsdb"
          object_store = "filesystem"
          schema       = "v13"
          index        = { prefix = "index_", period = "24h" }
        }]
      }
    }
    singleBinary = {
      replicas     = 1
      nodeSelector = local.node_selector
      persistence = {
        enabled      = var.enable_persistence
        size         = "10Gi"
        storageClass = var.storage_class
      }
    }
    read     = { replicas = 0 }
    write    = { replicas = 0 }
    backend  = { replicas = 0 }
    # Kind single-node: memcached caches OOM the control-plane
    chunksCache  = { enabled = false }
    resultsCache = { enabled = false }
    gateway = {
      enabled = true
      service = merge(
        { type = var.loki_service_type },
        var.loki_node_port > 0 ? { nodePort = var.loki_node_port } : {}
      )
    }
    test = { enabled = false }
    monitoring = {
      selfMonitoring = { enabled = false, grafanaAgent = { installOperator = false } }
      lokiCanary     = { enabled = false }
    }
  })]

  wait    = true
  timeout = 600
}

resource "helm_release" "promtail" {
  count = var.enable_promtail ? 1 : 0

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

# Sidecar-picked datasources (Prometheus + Loki UIDs match am-obs bindings).
resource "kubernetes_config_map_v1" "datasources" {
  metadata {
    name      = "grafana-datasources-fleet"
    namespace = var.namespace
    labels = {
      grafana_datasource = "1"
    }
  }

  data = {
    "datasources.yaml" = yamlencode({
      apiVersion = 1
      datasources = [
        {
          name      = "Prometheus"
          type      = "prometheus"
          uid       = "prometheus"
          access    = "proxy"
          url       = "http://prometheus-server.${var.namespace}.svc.cluster.local"
          isDefault = true
          editable  = true
          jsonData  = { timeInterval = "15s" }
        },
        {
          name     = "Loki"
          type     = "loki"
          uid      = "loki"
          access   = "proxy"
          url      = "http://loki-gateway.${var.namespace}.svc.cluster.local"
          editable = true
          jsonData = { maxLines = 1000 }
        }
      ]
    })
  }

  depends_on = [helm_release.grafana]
}

output "grafana_host" {
  value = local.grafana_host
}

output "namespace" {
  value = var.namespace
}

output "grafana_node_port" {
  value = var.grafana_node_port
}

output "loki_node_port" {
  value = var.loki_node_port
}

output "prometheus_node_port" {
  value = var.prometheus_node_port
}

output "prometheus_host" {
  value = "prometheus${local.domain_suffix}.${var.root_domain}"
}
