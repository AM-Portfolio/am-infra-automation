/**
 * 🔐 Vault Secret Reader — Shared Library
 * 
 * Provides a helper that generates the correct Terraform `data` source block
 * snippet for fetching secrets from the Vault KV-V2 engine.
 *
 * USAGE: This documents the pattern that all terraform layers MUST use
 * to read their secrets from Vault.
 *
 * PATHS:
 *   secret/infra/gateway       → cloudflare_token, cloudflare_account_id, zone_id, tunnel_secret
 *   secret/infra/databases     → postgresql_password, mongodb_password, redis_password, influxdb_token, grafana_password
 *   secret/infra/platform      → github_pat
 *   secret/infra/identity      → authentik_bootstrap_token, authentik_secret_key
 *   secret/infra/db-users/*    → app-specific db credentials
 */

const VAULT_SECRET_PATHS = {
  gateway:   'secret/infra/gateway',
  databases: 'secret/infra/databases',
  platform:  'secret/infra/platform',
  identity:  'secret/infra/identity',
};

/**
 * Returns the Terraform HCL snippet for reading a secret path.
 * Useful for documentation and code generation purposes.
 */
function getDataSourceSnippet(name, path) {
  return `
data "vault_kv_secret_v2" "${name}" {
  mount = "secret"
  name  = "${path.replace('secret/', '')}"
}
# Usage: data.vault_kv_secret_v2.${name}.data["<key>"]
`.trim();
}

module.exports = { VAULT_SECRET_PATHS, getDataSourceSnippet };
