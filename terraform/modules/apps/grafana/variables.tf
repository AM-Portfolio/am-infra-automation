variable "root_domain" {
  description = "Root domain (e.g. asrax.in)"
  type        = string
}

variable "namespace" {
  type    = string
  default = "monitoring"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "use_bare_fqdn" {
  description = "If true, Grafana/Loki/Prometheus public hosts are bare (grafana|loki|prometheus.root_domain). Required for the shared fleet obs hub used by all envs."
  type        = bool
  default     = false
}

variable "infra_namespace" {
  type    = string
  default = "infra"
}

variable "grafana_admin_user" {
  type    = string
  default = "admin"
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
}

variable "grafana_client_id" {
  type    = string
  default = "grafana"
}

variable "grafana_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "issuer_url" {
  description = "OIDC issuer (Keycloak realm URL or Authentik issuer)"
  type        = string
  default     = ""
}

variable "oidc_provider" {
  description = "keycloak | authentik | none"
  type        = string
  default     = "keycloak"
  validation {
    condition     = contains(["keycloak", "authentik", "none"], var.oidc_provider)
    error_message = "oidc_provider must be keycloak, authentik, or none."
  }
}

variable "disable_login_form" {
  description = "Hide Grafana local password form (OIDC-only). Phase 10 / ZT-P1."
  type        = bool
  default     = false
}

variable "enable_node_selector" {
  type    = bool
  default = true
}

variable "enable_promtail" {
  description = "Legacy in-cluster Promtail. Fleet uses Alloy on workload clusters instead."
  type        = bool
  default     = true
}

variable "enable_gateway" {
  description = "Create Traefik IngressRoute in the same cluster (legacy). Fleet uses cross-cluster-http."
  type        = bool
  default     = true
}

variable "enable_persistence" {
  type    = bool
  default = true
}

variable "storage_class" {
  type    = string
  default = "standard"
}

variable "grafana_service_type" {
  type    = string
  default = "ClusterIP"
}

variable "loki_service_type" {
  type    = string
  default = "ClusterIP"
}

variable "prometheus_service_type" {
  type    = string
  default = "ClusterIP"
}

variable "grafana_node_port" {
  type    = number
  default = 0
}

variable "loki_node_port" {
  type    = number
  default = 0
}

variable "prometheus_node_port" {
  type    = number
  default = 0
}

variable "grafana_chart_version" {
  type    = string
  default = "8.5.8"
}

variable "prometheus_chart_version" {
  type    = string
  default = "25.27.0"
}

variable "loki_chart_version" {
  type    = string
  default = "6.16.0"
}

variable "grafana_resources" {
  type = map(any)
  default = {
    requests = { cpu = "100m", memory = "256Mi" }
    limits   = { cpu = "500m", memory = "512Mi" }
  }
}
