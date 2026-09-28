# oauth2-proxy in front of consoles without native OIDC (iam-sso Phase 2).
# Upstream app Service must be ClusterIP; IngressRoute / NodePort points here first.

variable "name" {
  type        = string
  description = "Release / resource name suffix (e.g. kafka-ui)."
}

variable "namespace" {
  type    = string
  default = "infra"
}

variable "issuer_url" {
  type        = string
  description = "Keycloak issuer, e.g. https://auth.asrax.in/realms/am-realm"
}

variable "client_id" {
  type = string
}

variable "client_secret" {
  type      = string
  sensitive = true
}

variable "upstream" {
  type        = string
  description = "Upstream URL, e.g. http://kafka-ui.infra.svc:8080"
}

variable "redirect_url" {
  type        = string
  description = "https://kafka-ui.asrax.in/oauth2/callback"
}

variable "cookie_secret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "email_domains" {
  type    = list(string)
  default = ["*"]
}

variable "allowed_groups" {
  type        = list(string)
  default     = ["am-admin", "am-ops", "am-viewer"]
  description = "Keycloak groups/roles allowed through the proxy (am-user denied)."
}

variable "host" {
  type        = string
  default     = ""
  description = "When set, create Traefik IngressRoute for this host → oauth2-proxy."
}

variable "middleware_namespace" {
  type    = string
  default = "infra"
}

variable "node_port" {
  type        = number
  default     = 0
  description = "Optional NodePort for cross-cluster-http backends."
}

variable "enable_gateway" {
  type    = bool
  default = true
}

resource "random_password" "cookie" {
  count   = var.cookie_secret == "" ? 1 : 0
  length  = 32
  special = false
}

locals {
  cookie = var.cookie_secret != "" ? var.cookie_secret : random_password.cookie[0].result
  groups = join(",", var.allowed_groups)
}

resource "helm_release" "oauth2_proxy" {
  name       = "oauth2-proxy-${var.name}"
  repository = "https://oauth2-proxy.github.io/manifests"
  chart      = "oauth2-proxy"
  namespace  = var.namespace
  version    = "7.7.26"

  values = [yamlencode({
    config = {
      clientID     = var.client_id
      clientSecret = var.client_secret
      cookieSecret = local.cookie
      configFile   = <<-EOT
        provider = "keycloak-oidc"
        oidc_issuer_url = "${var.issuer_url}"
        email_domains = [ "${join("\", \"", var.email_domains)}" ]
        upstreams = [ "${var.upstream}" ]
        redirect_url = "${var.redirect_url}"
        scope = "openid email profile roles groups"
        code_challenge_method = "S256"
        oidc_groups_claim = "groups"
        allowed_groups = [ "${join("\", \"", var.allowed_groups)}" ]
        skip_provider_button = true
        reverse_proxy = true
        cookie_secure = true
      EOT
    }
    service = {
      type       = "ClusterIP"
      portNumber = 80
    }
  })]
}

resource "kubernetes_service_v1" "nodeport" {
  count = var.node_port > 0 ? 1 : 0
  metadata {
    name      = "oauth2-proxy-${var.name}-nodeport"
    namespace = var.namespace
  }
  spec {
    type = "NodePort"
    selector = {
      "app.kubernetes.io/name"     = "oauth2-proxy"
      "app.kubernetes.io/instance" = "oauth2-proxy-${var.name}"
    }
    port {
      name        = "http"
      port        = 80
      target_port = 80
      node_port   = var.node_port
    }
  }
  depends_on = [helm_release.oauth2_proxy]
}

resource "kubectl_manifest" "ingressroute" {
  count = var.enable_gateway && var.host != "" ? 1 : 0
  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: IngressRoute
    metadata:
      name: oauth2-proxy-${var.name}
      namespace: ${var.namespace}
    spec:
      entryPoints: [web, websecure]
      routes:
        - match: Host(`${var.host}`)
          kind: Rule
          priority: 9000
          services:
            - name: oauth2-proxy-${var.name}
              port: 80
          middlewares:
            - name: force-https-proto
              namespace: ${var.middleware_namespace}
  YAML
  depends_on = [helm_release.oauth2_proxy]
}

output "service_name" {
  value = "oauth2-proxy-${var.name}"
}

output "node_port" {
  value = var.node_port
}
