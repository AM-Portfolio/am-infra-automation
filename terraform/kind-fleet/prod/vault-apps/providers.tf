provider "vault" {
  address          = "https://vault.asrax.in"
  token            = jsondecode(replace(file("/data/am-state/vault-prod-infra.json"), "\ufeff", "")).root_token
  skip_child_token = true
}
