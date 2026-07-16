# ==============================================================================
# Port Exposer Variables
# ==============================================================================

variable "mappings" {
  description = "List of objects defining host-to-cluster port mappings"
  type = list(object({
    name        = string
    host_port   = number
    target_host = string
    target_port = number
  }))
}

variable "container_name" {
  description = "Name for the port-forwarder container"
  type        = string
  default     = "am-port-exposer"
}
