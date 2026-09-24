# Argo CD on platform. prune: false. OIDC to Keycloak client argocd.

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
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }
}

resource "random_password" "admin" {
  length  = 24
  special = false
}

locals {
  domain_suffix      = var.environment == "prod" ? "" : "-${var.environment}"
  argocd_host        = "argocd${local.domain_suffix}.${var.root_domain}"
  http_port          = 80
  argocd_admin_hash  = bcrypt(random_password.admin.result)
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  wait             = true
  timeout          = 900

  values = [yamlencode({
    global = {
      domain = local.argocd_host
    }
    configs = {
      params = {
        "server.insecure" = true
      }
      cm = merge(
        {
          url = "https://${local.argocd_host}"
          "application.instanceLabelKey" = "argocd.argoproj.io/instance"
          "admin.enabled"                = var.disable_local_admin ? "false" : "true"
        },
        var.oidc_issuer != "" ? {
          "oidc.config" = <<-OIDC
            name: Keycloak
            issuer: ${var.oidc_issuer}
            clientID: argocd
            clientSecret: $oidc.argocd.clientSecret
            requestedScopes: ["openid", "profile", "email", "groups"]
          OIDC
        } : {}
      )
      secret = {
        argocdServerAdminPassword = local.argocd_admin_hash
      }
      rbac = {
        "policy.default" = "role:readonly"
        "policy.csv"     = "g, admin, role:admin\ng, am-admin, role:admin\ng, ops, role:admin\ng, am-ops, role:admin\ng, viewer, role:readonly\ng, am-viewer, role:readonly\ng, user, role:readonly\ng, am-user, role:readonly\n"
      }
    }
    server = {
      service = {
        type           = "NodePort"
        nodePortHttp   = var.node_port
        nodePortHttps  = var.node_port_https
      }
      ingress = { enabled = false }
      extraArgs = ["--insecure"]
      resources = {
        requests = { cpu = var.server_cpu_request, memory = var.server_memory_request }
        limits   = { cpu = var.server_cpu_limit, memory = var.server_memory_limit }
      }
    }
    controller = {
      # Fleet: do not prune unmanaged resources on VPS / laptop tracks
      args = {
        appResyncPeriod = "60"
      }
      resources = {
        requests = { cpu = var.controller_cpu_request, memory = var.controller_memory_request }
        limits   = { cpu = var.controller_cpu_limit, memory = var.controller_memory_limit }
      }
    }
    repoServer = {
      resources = {
        requests = { cpu = var.repo_server_cpu_request, memory = var.repo_server_memory_request }
        limits   = { cpu = var.repo_server_cpu_limit, memory = var.repo_server_memory_limit }
      }
    }
    applicationSet = { enabled = true }
    notifications  = { enabled = false }
    dex            = { enabled = false }
  })]
}

resource "kubernetes_secret_v1" "oidc" {
  count = var.enable_oidc_secret ? 1 : 0
  metadata {
    name      = "argocd-secret"
    namespace = var.namespace
    labels    = { "app.kubernetes.io/part-of" = "argocd" }
  }
  data = {
    "oidc.argocd.clientSecret" = var.oidc_client_secret
  }
}

resource "kubectl_manifest" "ingressroute" {
  count     = var.enable_gateway && var.gateway_same_cluster ? 1 : 0
  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: IngressRoute
    metadata:
      name: argocd
      namespace: ${var.namespace}
    spec:
      entryPoints:
        - web
        - websecure
      routes:
        - match: Host(`${local.argocd_host}`)
          kind: Rule
          services:
            - name: argocd-server
              port: ${local.http_port}
          middlewares:
            - name: force-https-proto
              namespace: ${var.gateway_middleware_namespace}
  YAML

  depends_on = [helm_release.argocd]
}

# Document prune:false — Argo Application default; enforce via ConfigMap annotation for operators.
resource "kubernetes_config_map_v1" "fleet_policy" {
  metadata {
    name      = "argocd-fleet-policy"
    namespace = var.namespace
  }
  data = {
    "prune"           = "false"
    "policy_note"     = "Fleet G16: set syncPolicy.automated.prune=false on all Applications."
    "infra_api_note"  = var.infra_api_server
  }
}

output "argocd_host" { value = local.argocd_host }
output "admin_password" {
  value     = random_password.admin.result
  sensitive = true
}
output "node_port" { value = var.node_port }
output "namespace" { value = var.namespace }
