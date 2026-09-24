terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes" }
    random     = { source = "hashicorp/random" }
    kubectl    = { source = "gavinbunney/kubectl" }
  }
}
