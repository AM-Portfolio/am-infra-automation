variable "namespace" {
  type    = string
  default = "infra"
}

variable "service_name" {
  type    = string
  default = "apps-traefik-bridge"
}

variable "service_port" {
  type    = number
  default = 80
}

variable "backend_ip" {
  description = "Apps Kind CP IP on kind docker network. Prefer empty + backend_host."
  type        = string
  default     = ""
}

variable "backend_host" {
  description = "Docker DNS name (e.g. am-prod-apps-control-plane)."
  type        = string
  default     = ""
}

variable "backend_port" {
  description = "Apps Traefik NodePort (web)."
  type        = number
  default     = 30080
}

variable "host_fqdns" {
  description = "Product UI FQDNs routed through apps Traefik."
  type        = list(string)
}

variable "middleware_name" {
  type    = string
  default = "force-https-proto"
}
