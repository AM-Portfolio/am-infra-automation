# Thin Contabo / prod consumer of reusable fleet-gaps + fleet-reconcile.
# No Contabo-specific drift math — observe → classify → act.

terraform {
  required_version = ">= 1.5"
  required_providers {
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
  }
}

variable "prometheus_url" {
  type        = string
  default     = "https://prometheus.asrax.in"
  description = "Prometheus base URL for am_release_info"
}

variable "env_regex" {
  type        = string
  default     = "prod"
  description = "Env label regex (prod first; use prod|dr for both)"
}

variable "service_regex" {
  type    = string
  default = ".*"
}

variable "dry_run" {
  type        = bool
  default     = true
  description = "Plan only (default). Set false + enable_mutations to act."
}

variable "enable_mutations" {
  type        = bool
  default     = false
  description = "Must be true with dry_run=false to run am gitops reconcile --apply"
}

variable "sync_order_path" {
  type        = string
  default     = ""
  description = "Absolute path to am-gitops/catalog/sync-order.yaml; empty = sibling discover"
}

variable "am_bin" {
  type    = string
  default = "am"
}

locals {
  # Prefer explicit path; else sibling am-gitops next to am-infra-automation
  # release-sync → prod → kind-fleet → terraform → am-infra-automation → am-repos/am-gitops
  _sibling_sync = "${path.module}/../../../../../am-gitops/catalog/sync-order.yaml"
  sync_order = var.sync_order_path != "" ? var.sync_order_path : (
    fileexists(local._sibling_sync) ? abspath(local._sibling_sync) : ""
  )
}

module "gaps" {
  source         = "../../../modules/ops/fleet-gaps"
  prometheus_url = var.prometheus_url
  env_regex      = var.env_regex
  service_regex  = var.service_regex
}

module "reconcile" {
  source           = "../../../modules/ops/fleet-reconcile"
  gaps             = module.gaps.gaps
  dry_run          = var.dry_run
  enable_mutations = var.enable_mutations
  sync_order_path  = local.sync_order
  am_bin           = var.am_bin
}

output "counts" {
  value = module.gaps.counts
}

output "gaps" {
  value = module.gaps.gaps
}

output "plan" {
  value = module.reconcile.plan
}

output "promql" {
  value = module.gaps.promql
}
