terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2024.12.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

locals {
  authentik_hostname = "${var.environment == "prod" ? "authentik" : "authentik-${var.environment}"}.${var.root_domain}"
}

# ------------------------------------------------------------------------------
# Authentik Identity Platform (Core Server)
# ------------------------------------------------------------------------------

resource "helm_release" "authentik" {
  name       = "authentik"
  repository = "https://charts.goauthentik.io"
  chart      = "authentik"
  namespace  = var.namespace
  version    = "2024.2.2"
  timeout    = 600

  values = [yamlencode({
    authentik = {
      secret_key = var.authentik_secret_key
      env = {
        AUTHENTIK_BOOTSTRAP_PASSWORD        = var.bootstrap_token
        AUTHENTIK_BOOTSTRAP_TOKEN           = var.bootstrap_token
        AUTHENTIK_FORCE_HTTPS               = "true"
        AUTHENTIK_OIDC__ISSUER_BASE_URL     = "https://${local.authentik_hostname}/"
        AUTHENTIK_LISTEN__TRUSTED_PROXY_IPS = "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
      }
      postgresql = {
        host     = "authentik-postgres.identity.svc.cluster.local"
        name     = "authentik"
        user     = "authentik"
        password = var.postgres_password
      }
      redis = {
        host = "authentik-redis.identity.svc.cluster.local"
      }
    }
    postgresql = { enabled = false }
    redis      = { enabled = false }
    server = {
      ingress = {
        enabled          = true
        hosts            = [local.authentik_hostname]
        ingressClassName = "traefik"
      }
      service = {
        type          = "NodePort"
        nodePortHttp  = 30900
        nodePortHttps = 30943
      }
    }
  })]


  

  wait = true

  lifecycle {
    prevent_destroy = false
  }
}

/*
resource "authentik_outpost" "embedded" {
  name = "authentik Embedded Outpost"
  type = "proxy"
  
  # Inject all proxy providers directly by taking an array of Provider IDs from variables
  protocol_providers = var.proxy_provider_ids

  config = jsonencode({
    authentik_host          = "https://${local.authentik_hostname}"
    authentik_host_insecure = false
    authentik_host_browser  = ""
    log_level               = "info"
    object_naming_template  = "ak-outpost-%(name)s"
    docker_network          = "authentik"
    docker_map_ports        = true
    kubernetes_replicas     = 1
    kubernetes_namespace    = var.namespace
    kubernetes_ingress_class = "traefik"
    kubernetes_service_type = "ClusterIP"
  })
}
*/
