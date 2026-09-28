variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_account_id" {
  type      = string
  sensitive = true
}

variable "root_domain" {
  type    = string
  default = "asrax.in"
}

variable "prod_tunnel_id" {
  description = "asrax-prod-tunnel UUID (Contabo / VPS1 fallback)."
  type        = string
}

variable "dr_tunnel_id" {
  description = "asrax-dr-tunnel UUID (VPS3 primary)."
  type        = string
}

variable "dr_pool_enabled" {
  description = "When false, DR origins are disabled so traffic stays on Contabo (no auto-failback). Human sets true after DR restore soak."
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email for CF load_balancing_health_alert (fall-to-Contabo). Empty skips notification policy."
  type        = string
  default     = ""
}

variable "monitor_interval" {
  description = "Health check interval seconds (Business min 15)."
  type        = number
  default     = 60
}

variable "monitor_retries" {
  type    = number
  default = 2
}

variable "monitor_timeout" {
  type    = number
  default = 7
}

variable "monitor_consecutive_down" {
  description = "Consecutive failures before origin unhealthy — keep low for RTO."
  type        = number
  default     = 2
}

variable "monitor_consecutive_up" {
  description = "Consecutive successes before healthy again (failback still gated by dr_pool_enabled)."
  type        = number
  default     = 3
}
