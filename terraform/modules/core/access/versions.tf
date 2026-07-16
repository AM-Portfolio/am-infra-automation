terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2024.2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.25.0"
    }
  }
}
