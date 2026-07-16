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
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.2.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.0"
    }
  }
}

provider "docker" {
  host = var.environment == "local" ? "npipe:////./pipe/docker_engine" : "unix:///var/run/docker.sock"
}

provider "kubernetes" {
  host                   = "https://127.0.0.1:6443"
  insecure               = true
  config_path            = "./kubeconfig.yaml"
}

provider "helm" {
  kubernetes {
    host                   = "https://127.0.0.1:6443"
    insecure               = true
    config_path            = "./kubeconfig.yaml"
  }
}

provider "kubectl" {
  host                   = "https://127.0.0.1:6443"
  insecure               = true
  config_path            = "./kubeconfig.yaml"
  load_config_file       = true
}

# Vault provider initialized against the central instance
provider "vault" {
  address = "http://localhost:8200"
}

