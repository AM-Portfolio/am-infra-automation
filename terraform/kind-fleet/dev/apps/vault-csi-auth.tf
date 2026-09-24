# G25 — Vault CSI auth for apps+agents (Terraform).
# Requires: vault-dev up, ~/.asrax/vault-dev-infra.json, docker (apps CP IP).
# GHCR: prefer Docker Desktop credential helper (working), fallback credentials.env.

locals {
  vault_keys_file      = pathexpand("~/.asrax/vault-dev-infra.json")
  credentials_env_file = pathexpand("~/.asrax/credentials.env")
  credentials_raw      = fileexists(local.credentials_env_file) ? replace(file(local.credentials_env_file), "\r\n", "\n") : ""

  ghcr_token_matches = regexall("(?m)^(?:GHCR_TOKEN|GITHUB_TOKEN|GH_TOKEN|GITHUB_PERSONAL_ACCESS_TOKEN)=\"?([^\"\\n]+)\"?", local.credentials_raw)
  ghcr_user_matches  = regexall("(?m)^(?:GHCR_USERNAME|GITHUB_USER|GITHUB_USERNAME)=\"?([^\"\\n]+)\"?", local.credentials_raw)
  env_ghcr_user      = length(local.ghcr_user_matches) > 0 ? trimspace(local.ghcr_user_matches[0][0]) : ""
  env_ghcr_token     = length(local.ghcr_token_matches) > 0 ? trimspace(local.ghcr_token_matches[0][0]) : ""

  # Docker Desktop helper wins when present (credentials.env tokens often lack package:read).
  docker_ghcr_user  = try(data.external.ghcr_docker_cred.result.username, "")
  docker_ghcr_token = try(data.external.ghcr_docker_cred.result.secret, "")
  ghcr_username     = local.docker_ghcr_token != "" ? local.docker_ghcr_user : local.env_ghcr_user
  ghcr_token        = local.docker_ghcr_token != "" ? local.docker_ghcr_token : local.env_ghcr_token
  has_ghcr_token    = nonsensitive(length(local.ghcr_token) > 0)

  cluster_ca_raw = module.cluster.cluster_ca_certificate
  cluster_ca_pem = strcontains(local.cluster_ca_raw, "BEGIN CERTIFICATE") ? local.cluster_ca_raw : base64decode(local.cluster_ca_raw)

  apps_api_host = "https://${data.external.apps_cp_ip.result.ip}:6443"
}

data "external" "ghcr_docker_cred" {
  program = [
    "powershell",
    "-NoProfile",
    "-Command",
    <<-EOT
      try {
        $c = ('ghcr.io' | docker-credential-desktop get | ConvertFrom-Json)
        if (-not $c.Secret) { throw 'empty' }
        $u = ($c.Username -replace '\\','\\\\' -replace '"','\\"')
        $s = ($c.Secret -replace '\\','\\\\' -replace '"','\\"')
        Write-Output ('{"username":"' + $u + '","secret":"' + $s + '"}')
      } catch {
        Write-Output '{"username":"","secret":""}'
      }
    EOT
  ]
}

# Vault pod (infra) must TokenReview against the apps control-plane Docker IP, not localhost:6444.
data "external" "apps_cp_ip" {
  program = [
    "powershell",
    "-NoProfile",
    "-Command",
    <<-EOT
      $name = '${module.cluster.cluster_name}-control-plane'
      $ip = (docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $name 2>$null | Select-Object -First 1)
      if (-not $ip) { throw "docker inspect failed for $name" }
      Write-Output ('{"ip":"' + $ip.Trim() + '"}')
    EOT
  ]

  depends_on = [module.cluster]
}

module "vault_csi_auth" {
  source = "../../../modules/core/apps-vault-csi-auth"

  env                   = local.env
  apps_ns               = kubernetes_namespace.am_apps.metadata[0].name
  agents_ns             = kubernetes_namespace.am_agents.metadata[0].name
  kubernetes_host       = local.apps_api_host
  kubernetes_ca_cert_pem = local.cluster_ca_pem
  auth_path             = module.naming.vault_auth_mount
  role_name             = module.naming.vault_role
  policy_name           = module.naming.vault_policy
  ghcr_username         = local.ghcr_username
  ghcr_token            = local.ghcr_token
  create_pull_secrets   = local.has_ghcr_token

  depends_on = [
    kubernetes_namespace.am_apps,
    kubernetes_namespace.am_agents,
  ]
}

output "vault_csi_auth_path" {
  value = module.vault_csi_auth.auth_path
}

output "vault_csi_bound_namespaces" {
  value = module.vault_csi_auth.bound_namespaces
}

output "vault_csi_pull_secrets" {
  value = module.vault_csi_auth.pull_secrets_created
}

output "vault_csi_apps_api_host" {
  value = local.apps_api_host
}

output "vault_csi_has_ghcr" {
  value = local.has_ghcr_token
}

output "vault_csi_ghcr_source" {
  value = local.docker_ghcr_token != "" ? "docker-credential-desktop" : (local.env_ghcr_token != "" ? "credentials.env" : "none")
}
