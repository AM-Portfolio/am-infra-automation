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

variable "vps_host" {
  description = "VPS SSH hostname"
  type        = string
  default     = ""
}

variable "vps_user" {
  description = "VPS SSH username"
  type        = string
  default     = "root"
}

variable "vps_ram_gb" {
  description = "The total RAM of the host in GB"
  type        = number
  default     = 32
}

