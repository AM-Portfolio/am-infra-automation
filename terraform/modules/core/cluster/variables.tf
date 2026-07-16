variable "cluster_name" {
  description = "The name of the Kind cluster"
  type        = string
}

variable "vps_ip" {
  description = "The public IP of the VPS"
  type        = string
  default     = ""
}
variable "vps_ram_gb" {
  description = "The total RAM of the host in GB"
  type        = number
  default     = 16
}

variable "config_output_path" {
  description = "Path where the unified admin config should be written (optional)"
  type        = string
  default     = ""
}
