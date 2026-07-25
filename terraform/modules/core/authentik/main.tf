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
      secret_key         = var.authentik_secret_key
      bootstrap_password = var.bootstrap_token
      bootstrap_token    = var.bootstrap_token
      force_https        = true
      oidc = {
        issuer_base_url = "https://${local.authentik_hostname}/"
      }
      listen = {
        trusted_proxy_ips = "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
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
    prevent_destroy = true
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
