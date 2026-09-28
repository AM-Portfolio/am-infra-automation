provider "vault" {
  address          = "https://vault-dr.asrax.in"
  token            = jsondecode(replace(file("/data/am-state/vault-dr-infra.json"), "\ufeff", "")).root_token
  skip_child_token = true
}
