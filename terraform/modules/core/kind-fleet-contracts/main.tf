# Pure fleet contracts (no providers / resources).
# Shared by edge FQDNs, apps-traefik-bridge Host() match, n8n NodePort selector.
# Tests: terraform -chdir=terraform/modules/core/kind-fleet-contracts init -backend=false && terraform test

variable "environment" {
  description = "Fleet env: prod | dev | dr (prod and bare names skip env suffix)."
  type        = string
  default     = "prod"
}

variable "root_domain" {
  type    = string
  default = "asrax.in"
}

variable "https_names" {
  description = "HTTPS host labels → name.root or name-env.root."
  type        = list(string)
  default     = []
}

variable "bare_https_names" {
  description = "Subset of https_names that never get an env suffix."
  type        = list(string)
  default     = []
}

variable "extra_fqdns" {
  description = "Full FQDNs (e.g. apex asrax.in) merged into https_fqdn."
  type        = list(string)
  default     = []
}

variable "host_fqdns" {
  description = "FQDNs for Traefik Host() || Host() bridge match."
  type        = list(string)
  default     = []
}

locals {
  https_fqdn_from_names = {
    for n in var.https_names :
    n => (
      var.environment == "prod" || contains(var.bare_https_names, n)
      ? "${n}.${var.root_domain}"
      : "${n}-${var.environment}.${var.root_domain}"
    )
  }
  record_name_from_names = {
    for n in var.https_names :
    n => (
      var.environment == "prod" || contains(var.bare_https_names, n)
      ? n
      : "${n}-${var.environment}"
    )
  }
  https_fqdn_extra = { for f in var.extra_fqdns : f => f }
  record_name_extra = {
    for f in var.extra_fqdns :
    f => (f == var.root_domain ? "@" : trimsuffix(f, ".${var.root_domain}"))
  }
  https_fqdn  = merge(local.https_fqdn_from_names, local.https_fqdn_extra)
  record_name = merge(local.record_name_from_names, local.record_name_extra)
  host_match  = join(" || ", [for h in var.host_fqdns : "Host(`${h}`)"])
  n8n_nodeport_selector = {
    "app.kubernetes.io/name"      = "n8n"
    "app.kubernetes.io/instance"  = "n8n"
    "app.kubernetes.io/component" = "main"
  }
}

output "https_fqdn" {
  value = local.https_fqdn
}

output "record_name" {
  value = local.record_name
}

output "host_match" {
  value = local.host_match
}

output "n8n_nodeport_selector" {
  value = local.n8n_nodeport_selector
}
