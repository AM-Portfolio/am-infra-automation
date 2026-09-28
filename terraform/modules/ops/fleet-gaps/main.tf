terraform {
  required_version = ">= 1.5"
  required_providers {
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0"
    }
  }
}

variable "prometheus_url" {
  type        = string
  description = "Prometheus base URL (no trailing slash), e.g. https://prometheus.asrax.in"
  default     = "https://prometheus.asrax.in"
}

variable "prometheus_query_path" {
  type        = string
  description = "Instant-query API path under prometheus_url"
  default     = "/api/v1/query"
}

variable "env_regex" {
  type        = string
  description = "Prometheus label matcher for env (regex)"
  default     = "prod|dr"
}

variable "service_regex" {
  type        = string
  description = "Optional service label matcher; .* = all"
  default     = ".*"
}

variable "argo_app_suffix_style" {
  type        = string
  description = "How to build argo_app: service-env (default)"
  default     = "service-env"
}

locals {
  # Instant query: presence gauge with comparison labels
  promql = "am_release_info{env=~\"${var.env_regex}\",service=~\"${var.service_regex}\"}"
  query_url = "${trimsuffix(var.prometheus_url, "/")}${var.prometheus_query_path}?query=${urlencode(local.promql)}"
}

data "http" "release_info" {
  url = local.query_url
  request_headers = {
    Accept = "application/json"
  }
  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Prometheus query failed HTTP ${self.status_code} for ${local.query_url}"
    }
  }
}

locals {
  raw     = jsondecode(data.http.release_info.response_body)
  results = try(local.raw.data.result, [])

  # Flatten metric labels → gap objects
  parsed = [
    for r in local.results : {
      service  = try(r.metric.service, "")
      env      = try(r.metric.env, "")
      mismatch = try(r.metric.mismatch, "unknown")
      drift    = try(r.metric.drift, "UNKNOWN")
      severity = try(r.metric.severity, "warn")
      kind     = try(r.metric.kind, "")
      app_ns   = try(r.metric.app_ns, "")
    }
    if try(r.metric.service, "") != "" && try(r.metric.env, "") != ""
  ]

  gaps = [
    for g in local.parsed : merge(g, {
      action = (
        g.mismatch == "main_ne_pin" ? "pin" :
        contains(["live_ne_pin", "argo_missing"], g.mismatch) ? "sync" :
        contains(["no_main", "no_pin"], g.mismatch) || g.drift == "UNKNOWN" ? "none" :
        g.mismatch == "ok" && g.drift == "SYNC" ? "none" :
        g.drift == "DRIFT" ? "pin" :
        "none"
      )
      argo_app = "${g.service}-${g.env}"
    })
  ]

  pin_gaps  = [for g in local.gaps : g if g.action == "pin"]
  sync_gaps = [for g in local.gaps : g if g.action == "sync"]
  none_gaps = [for g in local.gaps : g if g.action == "none"]
}

output "gaps" {
  description = "Typed gap list for fleet-reconcile / agents (stable schema)."
  value       = local.gaps
}

output "pin_gaps" {
  value = local.pin_gaps
}

output "sync_gaps" {
  value = local.sync_gaps
}

output "counts" {
  value = {
    total = length(local.gaps)
    pin   = length(local.pin_gaps)
    sync  = length(local.sync_gaps)
    none  = length(local.none_gaps)
  }
}

output "promql" {
  value = local.promql
}
