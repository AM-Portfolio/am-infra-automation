# ==============================================================================
# VAULT LAYER — Providers (local environment)
# Strict scoping: only providers needed to deploy Vault and seed KV secrets.
# ==============================================================================

terraform {
  backend "local" {}
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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2024.12.0"
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

# 2. Dynamic Vault Token Extraction — Reuses cluster secrets for zero-touch auth
data "kubernetes_secret" "vault_keys" {
  # Bootstrap Lock: Only try to read the secret if no root token was passed manually
  # This prevents Phase 1 crashes before the secret exists.
  count = var.vault_root_token == "" ? 1 : 0

  metadata {
    name      = "vault-unseal-keys"
    namespace = "vault"
  }
}

locals {
  # Fish the root token from the cluster secret; fallback to manual var if needed
  # We use the index [0] only if the data source was actually created.
  vault_root_token = var.vault_root_token != "" ? var.vault_root_token : (length(data.kubernetes_secret.vault_keys) > 0 ? jsondecode(data.kubernetes_secret.vault_keys[0].data["keys.json"]).root_token : "")
}

# 3. Vault Provider — Authenticated for secret persistence
provider "vault" {
  address = "http://127.0.0.1:8200"
  token   = local.vault_root_token
}

provider "authentik" {
  url   = "https://authentik-local.${var.root_domain}"
  token = var.authentik_token
}
