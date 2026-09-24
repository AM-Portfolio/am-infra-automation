variable "environment" {
  type = string
}

variable "root_domain" {
  type    = string
  default = "asrax.in"
}

variable "namespace" {
  type    = string
  default = "infra"
}

variable "host_label" {
  description = "DNS label without env suffix (auth, argocd, temporal, …)."
  type        = string
}

variable "use_bare_fqdn" {
  description = "If true, FQDN is host_label.root_domain (no env suffix). Shared obs hub."
  type        = bool
  default     = false
}

variable "service_name" {
  type = string
}

variable "service_port" {
  type    = number
  default = 80
}

variable "backend_ip" {
  description = "Kind node IP on the shared docker network. Prefer empty + backend_host so apply resolves via Docker DNS."
  type        = string
  default     = ""
}

variable "backend_host" {
  description = "Docker DNS name of the Kind node (e.g. am-dev-platform-control-plane). Resolved at apply via docker inspect; never bake a stale 172.19.x across restarts."
  type        = string
  default     = ""
}

variable "backend_port" {
  description = "NodePort on the platform cluster."
  type        = number
}
