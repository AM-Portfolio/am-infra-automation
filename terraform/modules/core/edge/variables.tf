variable "environment" {
  description = "Fleet env token: dev | prod | dr."
  type        = string
}

variable "root_domain" {
  type    = string
  default = "asrax.in"
}

variable "namespace" {
  type    = string
  default = "infra"
}

variable "tunnel_id" {
  description = "Existing Cloudflare tunnel ID (asrax-<env>-tunnel). Do not create a new tunnel here."
  type        = string
}

variable "cloudflare_account_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "manage_cloudflare" {
  description = "Write proxied CNAME + tunnel ingress (Traefik only)."
  type        = bool
  default     = false
}

variable "https_names" {
  description = "HTTPS host labels (prod or bare_https_names: name.asrax.in; else name-<env>.asrax.in)."
  type        = list(string)
  default = [
    "vault",
    "minio",
    "s3",
    "influx",
    "traefik",
    "pgadmin",
    "mongo-express",
    "kafka-ui",
    "redis-ui",
    "auth",
    "argocd",
  ]
}

variable "bare_https_names" {
  description = "Subset of https_names that always use name.root_domain (no env suffix). Shared obs hub for all envs — only the Grafana host's tunnel should list these in https_names."
  type        = list(string)
  default     = ["grafana", "loki", "prometheus"]
}

variable "extra_fqdns" {
  description = "Full FQDNs to add to tunnel ingress + DNS (e.g. apex asrax.in). Not derived from https_names labels."
  type        = list(string)
  default     = []
}

variable "tunnel_only_fqdns" {
  description = "Full FQDNs added to tunnel ingress only (no DNS). Used so DR can answer bare prod Host headers behind Cloudflare LB while *-dr DNS stays direct."
  type        = list(string)
  default     = []
}

variable "skip_dns_names" {
  description = "Keys from record_name that must not create cloudflare_record (LB owns those bare hostnames)."
  type        = list(string)
  default     = []
}

variable "extra_origin_ingress" {
  description = <<-EOT
    Additive map of full FQDN → origin URL for tunnel ingress (non-Traefik).
    Used by argo-kubeapi-patch consumers so kubeapi-*.asrax.in reaches Kind apiserver
    without replacing existing Traefik rules. Example:
      { "kubeapi-dev.asrax.in" = "https://host.docker.internal:6444" }
    DNS for these hosts is owned by modules/ops/argo-kubeapi-patch (not this map).
  EOT
  type        = map(string)
  default     = {}
}

variable "traefik_chart_version" {
  type    = string
  default = "27.0.2"
}
