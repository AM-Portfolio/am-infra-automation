# ------------------------------------------------------------------------------
# LOCAL ENVIRONMENT PROVIDERS configuration
# ------------------------------------------------------------------------------

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.24"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2024.12.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.2.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.20"
    }
  }
}

provider "kind" {}

provider "docker" {
  host = var.environment == "local" ? "npipe:////./pipe/docker_engine" : "unix:///var/run/docker.sock"
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
  insecure       = true
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kubeconfig_context
    insecure       = true
  }
}

provider "kubectl" {
  config_path      = var.kubeconfig_path
  config_context   = var.kubeconfig_context
  insecure         = true
  load_config_file = true
}

# Vault provider initialized against the central instance
provider "vault" {
  address = "http://localhost:8200"
}

provider "authentik" {
  url   = "https://authentik.${var.root_domain}"
  token = var.authentik_token
}

provider "cloudflare" {
  api_token = var.cloudflare_token != "" ? var.cloudflare_token : null
}

provider "postgresql" {
  host     = "localhost"
  port     = 5432
  username = "postgres"
  password = var.postgresql_password
  sslmode  = "disable"
}
