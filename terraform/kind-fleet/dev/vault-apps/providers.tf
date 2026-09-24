provider "vault" {
  address          = "https://vault-dev.asrax.in"
  token            = jsondecode(replace(file(pathexpand("~/.asrax/vault-dev-infra.json")), "\ufeff", "")).root_token
  skip_child_token = true
}
