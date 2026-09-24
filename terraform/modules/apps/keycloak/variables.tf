variable "namespace" {
  type    = string
  default = "identity"
}

variable "environment" {
  type = string
}

variable "root_domain" {
  type    = string
  default = "asrax.in"
}

variable "db_host" {
  type = string
}

variable "db_name" {
  type    = string
  default = "platform"
}

variable "db_user" {
  type    = string
  default = "keycloak"
}

variable "db_schema" {
  description = "PG schema on shared platform DB (fleet seed creates schema keycloak)."
  type        = string
  default     = "keycloak"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "admin_user" {
  type    = string
  default = "admin"
}

variable "chart_version" {
  type    = string
  default = "25.2.0"
}

variable "image_registry" {
  type    = string
  default = "docker.io"
}

variable "image_repository" {
  type    = string
  default = "bitnamilegacy/keycloak"
}

variable "image_tag" {
  type    = string
  default = "26.3.3-debian-12-r0"
}

variable "cpu_request" {
  type    = string
  default = "250m"
}

variable "cpu_limit" {
  type    = string
  default = "1000m"
}

variable "memory_request" {
  type    = string
  default = "768Mi"
}

variable "memory_limit" {
  type    = string
  default = "1Gi"
}

variable "create_test_users" {
  description = "Create am-admin-test and am-user-test in am-realm (passwords via outputs → Vault)."
  type        = bool
  default     = true
}

variable "node_port" {
  type    = number
  default = 30808
}

variable "enable_gateway" {
  type    = bool
  default = true
}

variable "gateway_same_cluster" {
  description = "When true, create IngressRoute in this cluster. Fleet keeps Traefik on infra — leave false."
  type        = bool
  default     = false
}

variable "gateway_middleware_namespace" {
  type    = string
  default = "infra"
}

variable "oidc_enabled" {
  type    = bool
  default = false
}

variable "manage_realm" {
  description = "Create am-realm, roles, and G24 OIDC clients via Admin API."
  type        = bool
  default     = true
}

variable "realm_name" {
  type    = string
  default = "am-realm"
}

variable "realm_roles" {
  type = list(string)
  # Canonical identity roles + temporary am-* aliases for Grafana/fleet migrate
  default = [
    "user", "viewer", "ops", "admin", "super_admin", "service",
    "am-admin", "am-ops", "am-viewer", "am-user",
  ]
}

variable "mfa_enforce" {
  description = "ZT-P1: require OTP on browser flow and disable password-grant on human clients. ZT-P0 leave false (OTP optional)."
  type        = bool
  default     = false
}

variable "otp_optional_enroll" {
  description = "ZT-P0: enable CONFIGURE_TOTP as optional required action so ops can enroll before mfa_enforce."
  type        = bool
  default     = true
}
