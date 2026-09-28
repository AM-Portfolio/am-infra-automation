terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
  }
}
