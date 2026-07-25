variable "github_pat" {
  description = "GitHub Personal Access Token for runner registration"
  type        = string
  sensitive   = true
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
  description = "VPS SSH password used for remote image build"
  type        = string
  sensitive   = true
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

variable "environment" {
  description = "Deployment environment (e.g., local, hostbet-vps)"
  type        = string
  default     = "local"
}

variable "infra_script_path" {
  description = "Path to scripts/infra.py from the repo root (relative)"
  type        = string
  default     = "scripts/infra.py"
}

variable "namespace" {
  description = "Target namespace for GitHub Runner"
  type        = string
  default     = "github-actions"
}
