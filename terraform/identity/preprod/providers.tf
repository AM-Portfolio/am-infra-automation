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
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.26.0"
    }
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = "~> 2.10.0"
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
  vault_root_token_effective = var.vault_root_token != "" ? var.vault_root_token : jsondecode(data.kubernetes_secret.vault_keys.data["keys.json"]).root_token
}

# 3. Vault provider — read token dynamically
provider "vault" {
  address = "http://localhost:8200"
  token   = local.vault_root_token_effective
}

# ── Read Identity secrets from Vault ──────────────────────────────────────────
# Path is environment-scoped: local → local/infra/identity, preprod → preprod/infra/identity
data "vault_kv_secret_v2" "identity" {
  mount = "secret"
  name  = "${var.environment}/infra/identity"
}


# Authentik provider — prioritizing environment-injected token for bootstrap recovery
provider "authentik" {
  url   = "http://localhost:9000"  # local port-forward / NodePort
  token = var.authentik_token != "" ? var.authentik_token : try(data.vault_kv_secret_v2.identity.data["authentik_bootstrap_token"], "")
}

provider "postgresql" {
  host            = "localhost"
  port            = 5432
  username        = "authentik"
  password        = local.creds.authentik_postgres
  database        = "authentik"
  sslmode         = "disable"
  connect_timeout = 15
}

provider "mongodbatlas" {
  # Local bypass logic will be in the module
}
