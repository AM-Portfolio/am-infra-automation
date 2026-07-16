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

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kubeconfig_context
  }
}

provider "kubectl" {
  config_path      = var.kubeconfig_path
  config_context   = var.kubeconfig_context
  load_config_file = true
}

# 2. Dynamic Vault Token Extraction
data "kubernetes_secret" "vault_keys" {
  metadata {
    name      = "vault-unseal-keys"
    namespace = "vault"
  }
}

locals {
  vault_root_token = var.vault_root_token != "" ? var.vault_root_token : jsondecode(data.kubernetes_secret.vault_keys.data["keys.json"]).root_token
}

# 3. Vault provider initialized against the central instance
provider "vault" {
  address = "http://localhost:8200"
  token   = local.vault_root_token
}

# Removed authentik and cloudflare providers for strict scoping

provider "postgresql" {
  host     = "localhost"
  port     = 5432
  username = "postgres"
  password = var.postgresql_password
  sslmode  = "disable"
}
