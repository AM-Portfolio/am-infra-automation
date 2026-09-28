provider "vault" {
  address          = "https://vault.asrax.in"
  token            = local.vault_token_resolved
  skip_child_token = true
}
