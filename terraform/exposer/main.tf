variable "mappings" {
  type = list(object({
    name        = string
    host_port   = number
    target_host = string
    target_port = number
  }))
}

module "port_exposer" {
  source   = "../modules/core/port-exposer"
  mappings = var.mappings
}
