provider "kubernetes" {
  host                   = module.cluster.endpoint
  client_certificate     = module.cluster.client_certificate
  client_key             = module.cluster.client_key
  cluster_ca_certificate = module.cluster.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host                   = module.cluster.endpoint
    client_certificate     = module.cluster.client_certificate
    client_key             = module.cluster.client_key
    cluster_ca_certificate = module.cluster.cluster_ca_certificate
  }
}

provider "vault" {
  address          = module.naming.vault_url
  token            = jsondecode(replace(file(pathexpand("~/.asrax/vault-dev-infra.json")), "\ufeff", "")).root_token
  skip_child_token = true
}
