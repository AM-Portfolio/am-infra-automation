# Prefer rewritten kubeconfig (127.0.0.1:6444). module.cluster.endpoint may be 0.0.0.0.
provider "kubernetes" {
  config_path    = local.apps_kubeconfig
  config_context = "kind-am-dr-apps"
}

provider "helm" {
  kubernetes {
    config_path    = local.apps_kubeconfig
    config_context = "kind-am-dr-apps"
  }
}

provider "vault" {
  address          = "https://vault-dr.asrax.in"
  token            = jsondecode(replace(file("/data/am-state/vault-dr-infra.json"), "\ufeff", "")).root_token
  skip_child_token = true
}
