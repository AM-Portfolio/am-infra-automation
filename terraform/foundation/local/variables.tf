 # ------------------------------------------------------------------------------
# PREPROD ENVIRONMENT VARIABLES
# ------------------------------------------------------------------------------

# Core
variable "root_domain" {
  description = "The primary domain name for the infrastructure services (e.g. munish.org)"
  type        = string
  default     = "munish.org"
}

variable "environment" {
  description = "Deployment environment name"
  type        = string
  default     = "local"
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "../../../k8s/kubeconfig.local"
}

variable "kubeconfig_context" {
  description = "Kubernetes context to use"
  type        = string
  default     = "kind-am-local"
}

# Authentik
variable "authentik_token" {
  description = "API Token for Authentik provider authentication"
  type        = string
  sensitive   = true
  default     = ""
}

# Cloudflare
variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for the root domain"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_tunnel_secret" {
  description = "Secret for the Cloudflare Tunnel"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_token" {
  description = "Cloudflare API Token for DNS and Tunnel management"
  type        = string
  sensitive   = true
  default     = ""
}


variable "vps_ip" {
  description = "Local loopback for development"
  type        = string
  default     = "127.0.0.1"
}

# GitHub Runner
variable "github_pat" {
  description = "GitHub Personal Access Token for runner registration"
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_repo_url" {
  description = "GitHub repository or org URL for runner registration"
  type        = string
  default     = "https://github.com/AM-Portfolio"
}

variable "github_org_name" {
  description = "GitHub organisation name"
  type        = string
  default     = "AM-Portfolio"
}

variable "vps_pass" {
  description = "VPS SSH password for remote image build"
  type        = string
  sensitive   = true
  default     = ""
}

# Database root passwords (passed from Vault of .env)
variable "postgresql_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "mongodb_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "redis_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "influxdb_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "grafana_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "pgadmin_password" {
  type      = string
  sensitive = true
  default   = ""
}


variable "influxdb_token" {
  type      = string
  sensitive = true
  default   = ""
}

# Per-application DB credentials (managed by module.db_users)
variable "am_auth_db_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "am_market_db_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "am_market_mongo_password" {
  type      = string
  sensitive = true
  default   = ""
}
variable "vps_ram_gb" {
  description = "The total RAM of the host in GB"
  type        = number
  default     = 32
}
