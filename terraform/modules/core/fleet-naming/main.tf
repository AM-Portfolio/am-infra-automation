# Shared env-derived names for kind-fleet stacks (apps / agents / vault / edge).
# Stack folders still hardcode local.env once; everything else comes from here.

locals {
  env    = var.env
  domain = var.domain

  apps_ns   = "am-apps-${local.env}"
  agents_ns = "am-agents-${local.env}"

  # Prod vault/UI historically omit the env infix in the public hostname.
  vault_host = local.env == "prod" ? "vault.${local.domain}" : "vault-${local.env}.${local.domain}"
  ui_host    = local.env == "prod" ? "am.${local.domain}" : "am-${local.env}.${local.domain}"
  auth_host  = local.env == "prod" ? "auth.${local.domain}" : "auth-${local.env}.${local.domain}"

  vault_url        = "https://${local.vault_host}"
  vault_auth_mount = "kubernetes-apps"
  vault_role       = "am-backend-role"
  vault_policy     = "am-apps-read"
  vault_data_prefix = "apps/data/${local.env}"

  middleware_cors  = "${local.env}-global-cors"
  middleware_strip = "${local.env}-strip-prefix"

  apps_cluster_name = "am-${local.env}-apps"
  kubeconfig_apps   = "~/.asrax/kubeconfig.am-${local.env}-apps.yaml"
}
