variable "env" {
  description = "Business env token. Must be dev, prod, dr, or obs. Never local, preprod, or hostbet-vps."
  type        = string

  validation {
    condition     = contains(["dev", "prod", "dr", "obs"], var.env)
    error_message = "env must be one of: dev, prod, dr, obs. Refusing local, preprod, hostbet-vps, and any other token."
  }
}

variable "cluster_role" {
  description = "Fleet role on this host: infra, apps, platform, or obs."
  type        = string

  validation {
    condition     = contains(["infra", "apps", "platform", "obs"], var.cluster_role)
    error_message = "cluster_role must be one of: infra, apps, platform, obs."
  }
}

variable "api_server_port" {
  description = "Kind API port. Leave null to use role defaults: infra/obs 6443, apps 6444, platform 6445."
  type        = number
  default     = null

  validation {
    condition     = var.api_server_port == null || contains([6443, 6444, 6445], var.api_server_port)
    error_message = "api_server_port must be 6443, 6444, or 6445."
  }
}

variable "node_shape" {
  description = "one = single control-plane (dev/dr/obs). two = control-plane + worker (prod). Leave null to derive from env."
  type        = string
  default     = null

  validation {
    condition     = var.node_shape == null || contains(["one", "two"], var.node_shape)
    error_message = "node_shape must be one or two."
  }
}

variable "api_server_address" {
  description = "Kind API listen address. Laptop uses 127.0.0.1; VPS may set 0.0.0.0."
  type        = string
  default     = "127.0.0.1"
}

variable "vps_ip" {
  description = "Public IP added as an API cert SAN when non-empty."
  type        = string
  default     = ""
}

variable "vps_ram_gb" {
  description = "Host RAM in GB (reserved for later sizing)."
  type        = number
  default     = 16
}

variable "config_output_path" {
  description = "Optional kubeconfig write path. Empty skips the access provisioner (Phase 1 validate)."
  type        = string
  default     = ""
}

variable "enable_data_mount" {
  description = "Mount host data dir into the control-plane. Off by default so a laptop does not need /mnt/am-infra/data."
  type        = bool
  default     = false
}

variable "data_host_path" {
  description = "Host path for the optional data mount."
  type        = string
  default     = "/mnt/am-infra/data"
}

variable "enable_etcd_ram_mount" {
  description = "Mount host RAM disk over etcd. Off by default so a laptop does not need /mnt/etcd-ram."
  type        = bool
  default     = false
}

variable "etcd_ram_host_path" {
  description = "Host path for the optional etcd RAM mount."
  type        = string
  default     = "/mnt/etcd-ram"
}

variable "cluster_name" {
  description = "Unused. Fleet names are computed from env + cluster_role. Do not pass this."
  type        = string
  default     = ""

  validation {
    condition     = var.cluster_name == ""
    error_message = "Do not pass cluster_name. Kind name is computed: am-<env>-<role> or am-obs. Never am-preprod or am-local."
  }
}
