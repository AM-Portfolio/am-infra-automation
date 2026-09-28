# Phase 6 — Alloy on Contabo preprod (am-vps-nonprod) → bare Loki/Prom.
# Standalone root: apply from laptop (or jump host) with kubeconfig present.
#   cd terraform/kind-fleet/preprod/apps && terraform init && terraform apply

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

provider "kubernetes" {
  config_path = pathexpand("~/.asrax/kubeconfig.am-vps-nonprod.yaml")
}

provider "helm" {
  kubernetes {
    config_path = pathexpand("~/.asrax/kubeconfig.am-vps-nonprod.yaml")
  }
}

locals {
  loki_push_url               = "https://loki.asrax.in/loki/api/v1/push"
  prometheus_remote_write_url = "https://prometheus.asrax.in/api/v1/write"
}

module "alloy_logs" {
  source = "../../../modules/core/alloy-logs"

  namespace                    = "monitoring"
  cluster_name                = "am-vps-nonprod"
  environment                 = "preprod"
  vps                         = "vps-preprod"
  vps_name                    = "VPS_PREPROD"
  vps_ip                      = "103.127.146.57"
  loki_push_url               = local.loki_push_url
  prometheus_remote_write_url = local.prometheus_remote_write_url
}

output "alloy_namespace" {
  value = module.alloy_logs.namespace
}

output "alloy_loki_push_url" {
  value = local.loki_push_url
}

output "alloy_prometheus_remote_write_url" {
  value = local.prometheus_remote_write_url
}
