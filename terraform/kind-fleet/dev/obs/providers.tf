provider "kubernetes" {
  config_path    = pathexpand("~/.asrax/kubeconfig.am-dev-platform.yaml")
  config_context = "kind-am-dev-platform"
}

provider "helm" {
  kubernetes {
    config_path    = pathexpand("~/.asrax/kubeconfig.am-dev-platform.yaml")
    config_context = "kind-am-dev-platform"
  }
}

provider "kubectl" {
  config_path      = pathexpand("~/.asrax/kubeconfig.am-dev-platform.yaml")
  config_context   = "kind-am-dev-platform"
  load_config_file = true
}

provider "kubernetes" {
  alias          = "infra"
  config_path    = pathexpand("~/.asrax/kubeconfig.am-dev-infra.yaml")
  config_context = "kind-am-dev-infra"
}

provider "kubectl" {
  alias            = "infra"
  config_path      = pathexpand("~/.asrax/kubeconfig.am-dev-infra.yaml")
  config_context   = "kind-am-dev-infra"
  load_config_file = true
}

variable "platform_node_ip" {
  type    = string
  default = ""
}

variable "vault_addr" {
  type    = string
  default = "https://vault-dev.asrax.in"
}

variable "vault_token" {
  type      = string
  sensitive = true
  default   = ""
}
