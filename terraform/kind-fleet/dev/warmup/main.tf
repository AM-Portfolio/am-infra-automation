# Post-restart staged warmup for kind-fleet DEV.
# Discovers ALL Deployments + StatefulSets in every non-system namespace, batches of 5.
# State: ~/.asrax/tfstate/dev/warmup/
# Operator: terraform apply -var='warmup_generation=YYYYMMDD-HHMM'

locals {
  env = "dev"
}

resource "terraform_data" "env_folder_guard" {
  input = local.env
  lifecycle {
    precondition {
      condition     = local.env == "dev"
      error_message = "kind-fleet/dev/warmup must set local.env = \"dev\"."
    }
  }
}

module "warmup" {
  source = "../../../modules/core/staged-workload-warmup"

  environment          = local.env
  batch_size           = var.batch_size
  warmup_generation    = var.warmup_generation
  per_app_timeout_sec  = var.per_app_timeout_sec
  gate_timeout_sec     = var.gate_timeout_sec
  skip_gates           = var.skip_gates
  skip_workloads       = var.skip_workloads
  skip_bridge_refresh  = var.skip_bridge_refresh
  namespaces           = var.namespaces
  exclude_namespaces   = var.exclude_namespaces
  kubeconfig           = var.kubeconfig
}

variable "warmup_generation" {
  description = "Bump after host/Docker restart to re-run staged warmup."
  type        = string
}

variable "batch_size" {
  type    = number
  default = 5
}

variable "per_app_timeout_sec" {
  type    = number
  default = 480
}

variable "gate_timeout_sec" {
  type    = number
  default = 300
}

variable "skip_gates" {
  type    = bool
  default = false
}

variable "skip_workloads" {
  type    = bool
  default = false
}

variable "skip_bridge_refresh" {
  type    = bool
  default = false
}

variable "namespaces" {
  description = "Optional comma-separated allowlist. Empty = all NS except denylist."
  type        = string
  default     = ""
}

variable "exclude_namespaces" {
  type    = string
  default = ""
}

variable "kubeconfig" {
  type    = string
  default = ""
}

output "warmup_generation" {
  value = module.warmup.warmup_generation
}

output "batch_size" {
  value = module.warmup.batch_size
}
