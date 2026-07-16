variable "root_domain" {
  description = "The base domain (e.g., munish.org)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace where cloudflared will be deployed"
  type        = string
}

variable "environment" {
  description = "The execution environment (local|preprod) used for subdomain prefixing"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID (Optional if root_domain is provided for auto-discovery)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_tunnel_secret" {
  description = "Cloudflare Tunnel Secret (Optional in Token-First mode)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vps_ip" {
  description = "Public IP of the VPS hosting the Kind cluster (used for any direct A records if needed)"
  type        = string
  default     = ""
}

variable "cloudflare_tunnel_id" {
  description = "ID of an existing Cloudflare tunnel to reuse. If empty, a new tunnel will be created."
  type        = string
  sensitive   = true
  default     = ""
}
