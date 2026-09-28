terraform {
  required_version = ">= 1.5"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
  }
}

variable "gaps" {
  type = list(object({
    service  = string
    env      = string
    action   = string
    mismatch = optional(string, "")
    drift    = optional(string, "")
    severity = optional(string, "")
    argo_app = optional(string, "")
    kind     = optional(string, "")
    app_ns   = optional(string, "")
  }))
  description = "Gap list from module.fleet-gaps (or hand-built for tests)."
}

variable "dry_run" {
  type        = bool
  default     = true
  description = "When true, only emit plan output — no promote or sync."
}

variable "enable_mutations" {
  type        = bool
  default     = false
  description = "When true and dry_run=false, run a single sequential am gitops reconcile --apply."
}

variable "sync_order_path" {
  type        = string
  default     = ""
  description = "Path to am-gitops/catalog/sync-order.yaml (wave order for sync actions)."
}

variable "batch_size" {
  type        = number
  default     = 0
  description = "Override sync-order batchSize; 0 = use file (or 2)."
}

variable "am_bin" {
  type        = string
  default     = "am"
  description = "amctl binary for mutations (must be on PATH when enable_mutations)."
}

variable "gaps_file" {
  type        = string
  default     = ""
  description = "Optional path to write gaps JSON for am gitops reconcile --gaps-file; empty = path.module/.fleet-gaps.json"
}

locals {
  pin_gaps  = [for g in var.gaps : g if g.action == "pin"]
  sync_gaps = [for g in var.gaps : g if g.action == "sync"]

  sync_order_raw = var.sync_order_path != "" ? yamldecode(file(var.sync_order_path)) : tomap({})
  waves          = try(local.sync_order_raw.waves, {})
  batch_size     = var.batch_size > 0 ? var.batch_size : try(tonumber(local.sync_order_raw.batchSize), 2)

  # service → {wave, order}; missing → wave 999
  wave_index = merge(concat(
    [{}],
    [
      for w, names in local.waves : {
        for i, n in coalesce(names, []) : tostring(n) => {
          wave  = tonumber(w)
          order = i
        }
      }
    ]
  )...)

  sync_keyed = [
    for g in local.sync_gaps : merge(g, {
      _sort = format(
        "%04d-%04d-%s-%s",
        try(local.wave_index[g.service].wave, 999),
        try(local.wave_index[g.service].order, 999),
        g.env,
        g.service
      )
    })
  ]

  sync_sorted = [
    for k in sort([for g in local.sync_keyed : g._sort]) :
    [for g in local.sync_keyed : g if g._sort == k][0]
  ]

  do_mutate   = var.enable_mutations && !var.dry_run
  gaps_path   = var.gaps_file != "" ? var.gaps_file : "${path.module}/.fleet-gaps.json"
  envs_in_gaps = distinct([for g in var.gaps : g.env if contains(["pin", "sync"], g.action)])
  # reconcile CLI takes one --env; multi-env stacks call am twice or use env_regex via gaps-file
  primary_env = length(local.envs_in_gaps) > 0 ? local.envs_in_gaps[0] : "prod"
}

# Plan-only artifact for agents / terraform output (always written when mutating so CLI has SoT)
resource "local_file" "gaps_json" {
  count    = local.do_mutate ? 1 : 0
  content  = jsonencode(var.gaps)
  filename = local.gaps_path
}

# Single sequential runner — never for_each sync (Kind RAM/CPU). Batches inside amctl.
resource "terraform_data" "reconcile" {
  count = local.do_mutate ? 1 : 0

  input = {
    pin_count  = length(local.pin_gaps)
    sync_count = length(local.sync_gaps)
    batch_size = local.batch_size
    gaps_sha   = sha256(jsonencode(var.gaps))
  }

  provisioner "local-exec" {
    command = "${var.am_bin} gitops reconcile --gaps-file \"${local_file.gaps_json[0].filename}\" --apply --batch-size ${local.batch_size}"
  }

  depends_on = [local_file.gaps_json]
}

output "plan" {
  description = "Actions that would run (or did run via am gitops reconcile)."
  value = {
    dry_run          = var.dry_run
    enable_mutations = var.enable_mutations
    pin = [
      for g in local.pin_gaps : {
        service = g.service
        env     = g.env
        command = "am gitops promote ${g.service} --env ${g.env}"
      }
    ]
    sync = [
      for g in local.sync_sorted : {
        service  = g.service
        env      = g.env
        argo_app = coalesce(g.argo_app, "${g.service}-${g.env}")
        command  = "am gitops sync ${g.service} --env ${g.env}"
      }
    ]
    batch_size = local.batch_size
  }
}

output "pin_count" {
  value = length(local.pin_gaps)
}

output "sync_count" {
  value = length(local.sync_gaps)
}
