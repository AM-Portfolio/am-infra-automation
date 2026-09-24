terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.25"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.0"
    }
  }
}
