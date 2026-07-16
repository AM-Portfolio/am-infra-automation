terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes" }
    helm       = { source = "hashicorp/helm" }
    authentik  = { 
      source  = "goauthentik/authentik" 
      version = "~> 2024.12.0"
    }
    kubectl    = { source = "gavinbunney/kubectl" }
    vault      = { source = "hashicorp/vault" }
    cloudflare = { source = "cloudflare/cloudflare" }
  }
}
