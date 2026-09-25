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

variable "traefik_chart_version" {
  type    = string
  default = "27.0.2"
}
