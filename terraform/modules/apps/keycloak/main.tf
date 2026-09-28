# Keycloak on platform. Drop Authentik. JDBC via DNS-only postgres-<env>.asrax.in.

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.10.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }
}

locals {
  domain_suffix = var.environment == "prod" ? "" : "-${var.environment}"
  auth_host_env = "auth${local.domain_suffix}.${var.root_domain}"
  auth_host     = var.public_hostname != "" ? var.public_hostname : local.auth_host_env
  host_match = (
    var.public_hostname != "" && var.also_match_env_host && local.auth_host != local.auth_host_env
    ? "Host(`${local.auth_host}`) || Host(`${local.auth_host_env}`)"
    : "Host(`${local.auth_host}`)"
  )
  http_port = 8080
}

resource "random_password" "admin" {
  length  = 24
  special = false
}

resource "kubernetes_secret_v1" "db" {
  metadata {
    name      = "keycloak-db"
    namespace = var.namespace
  }
  data = {
    password = var.db_password
  }
}

resource "kubernetes_secret_v1" "admin" {
  metadata {
    name      = "keycloak-admin"
    namespace = var.namespace
  }
  data = {
    password = random_password.admin.result
  }
}

resource "helm_release" "keycloak" {
  name             = "keycloak"
  repository       = "oci://registry-1.docker.io/bitnamicharts"
  chart            = "keycloak"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  wait             = true
  timeout          = 900

  values = [yamlencode({
    global = {
      security = {
        allowInsecureImages = true
      }
    }
    image = {
      registry   = var.image_registry
      repository = var.image_repository
      tag        = var.image_tag
    }
    auth = {
      adminUser               = var.admin_user
      existingSecret          = kubernetes_secret_v1.admin.metadata[0].name
      passwordSecretKey       = "password"
    }
    production   = true
    proxyHeaders = "xforwarded"
    httpEnabled  = true
    extraEnvVars = [
      { name = "KC_HOSTNAME", value = local.auth_host },
      { name = "KC_HOSTNAME_STRICT", value = "false" },
      { name = "KC_HTTP_ENABLED", value = "true" },
      { name = "KC_PROXY_HEADERS", value = "xforwarded" },
      { name = "KC_METRICS_ENABLED", value = "true" },
      { name = "KC_HEALTH_ENABLED", value = "true" },
      # Legacy token-exchange (requested_subject / Google login impersonation) + FGAP v1
      { name = "KC_FEATURES", value = "token-exchange,admin-fine-grained-authz:v1" },
    ]
    metrics = {
      enabled = true
      service = {
        ports = {
          http = 8080
        }
      }
    }
    podAnnotations = {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "8080"
      "prometheus.io/path"   = "/metrics"
    }
    postgresql = { enabled = false }
    externalDatabase = {
      host                      = var.db_host
      port                      = 5432
      user                      = var.db_user
      database                  = var.db_name
      schema                    = var.db_schema
      existingSecret            = kubernetes_secret_v1.db.metadata[0].name
      existingSecretPasswordKey = "password"
    }
    service = {
      type = "NodePort"
      ports = {
        http = local.http_port
      }
      nodePorts = {
        http = var.node_port
      }
    }
    ingress = { enabled = false }
    resources = {
      requests = { cpu = var.cpu_request, memory = var.memory_request }
      limits   = { cpu = var.cpu_limit, memory = var.memory_limit }
    }
  })]
}

# Same-cluster IngressRoute (used when Traefik shares the cluster). Fleet uses cross-cluster-http on infra.
resource "kubectl_manifest" "ingressroute" {
  count     = var.enable_gateway && var.gateway_same_cluster ? 1 : 0
  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: IngressRoute
    metadata:
      name: keycloak
      namespace: ${var.namespace}
    spec:
      entryPoints:
        - web
        - websecure
      routes:
        - match: ${local.host_match}
          kind: Rule
          services:
            - name: keycloak
              port: ${local.http_port}
          middlewares:
            - name: force-https-proto
              namespace: ${var.gateway_middleware_namespace}
  YAML

  depends_on = [helm_release.keycloak]
}

output "auth_host" { value = local.auth_host }
output "admin_user" { value = var.admin_user }
output "admin_password" {
  value     = random_password.admin.result
  sensitive = true
}
output "node_port" { value = var.node_port }
output "http_port" { value = local.http_port }
output "namespace" { value = var.namespace }
