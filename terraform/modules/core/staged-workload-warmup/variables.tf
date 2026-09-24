variable "environment" {
  description = "Fleet env label (dev, preprod, prod, dr, or custom). Passed to warmup.ps1 as -Env."
  type        = string
  default     = "dev"
}

variable "batch_size" {
  description = "Workloads (Deployment+StatefulSet) restarted per batch after gates."
  type        = number
  default     = 5
}

variable "warmup_generation" {
  description = "Bump after host/Docker restart to re-run staged warmup."
  type        = string
}

variable "per_app_timeout_sec" {
  type    = number
  default = 480
}

variable "gate_timeout_sec" {
  type    = number
  default = 300
}

variable "skip_gates" {
  type    = bool
  default = false
}

variable "skip_workloads" {
  type    = bool
  default = false
}

variable "skip_bridge_refresh" {
  type    = bool
  default = false
}

variable "namespaces" {
  description = "Optional comma-separated NS allowlist. Empty = all NS except denylist."
  type        = string
  default     = ""
}

variable "exclude_namespaces" {
  description = "Extra comma-separated NS denylist merged with built-in system denylist."
  type        = string
  default     = ""
}

variable "kubeconfig" {
  description = "Optional override for apps-cluster kubeconfig. Empty = ~/.asrax convention."
  type        = string
  default     = ""
}
