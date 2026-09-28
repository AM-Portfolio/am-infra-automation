# One-shot Alloy apply roots (local kubeconfig). Same module as fleet alloy.tf.
# Usage: terraform -chdir=terraform/kind-fleet/_phase6-alloy/<name> init && apply

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

variable "kubeconfig" {
  type = string
}

variable "kube_context" {
  type    = string
  default = ""
}

variable "cluster_name" {
  type = string
}

variable "environment" {
  type = string
}

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig)
  config_context = var.kube_context != "" ? var.kube_context : null
}

provider "helm" {
  kubernetes {
    config_path    = pathexpand(var.kubeconfig)
    config_context = var.kube_context != "" ? var.kube_context : null
  }
}

module "alloy_logs" {
  source = "../../modules/core/alloy-logs"

  namespace                    = "monitoring"
  cluster_name                = var.cluster_name
  environment                 = var.environment
  loki_push_url               = "https://loki.asrax.in/loki/api/v1/push"
  prometheus_remote_write_url = "https://prometheus.asrax.in/api/v1/write"
}

output "alloy_namespace" {
  value = module.alloy_logs.namespace
}
