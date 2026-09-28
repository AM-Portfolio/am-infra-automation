# Phase 6: R2 → DR slave restore. Enable with r2-pull.auto.tfvars on VPS3.

variable "enable_r2_pull" {
  type    = bool
  default = false
}

variable "r2_pull_cloudflare_account_id" {
  type      = string
  default   = ""
  sensitive = true
}

variable "r2_pull_cloudflare_api_token" {
  type      = string
  default   = ""
  sensitive = true
}

variable "r2_pull_cloudflare_email" {
  type      = string
  default   = ""
  sensitive = true
}

variable "r2_pull_cloudflare_api_key" {
  type      = string
  default   = ""
  sensitive = true
}

module "r2_db_pull" {
  source    = "../../../modules/core/r2-db-pull"
  enabled   = var.enable_r2_pull
  namespace = module.namespaces.infra_ns
  schedule  = "30 */6 * * *"
  r2_bucket = "asrax-disaster"
  prefix    = "prod"

  kind_cluster_name     = "am-dr-infra"
  cloudflare_account_id = var.r2_pull_cloudflare_account_id
  cloudflare_api_token  = var.r2_pull_cloudflare_api_token
  cloudflare_email      = var.r2_pull_cloudflare_email
  cloudflare_api_key    = var.r2_pull_cloudflare_api_key
  redis_password        = random_password.redis.result

  depends_on = [
    module.postgresql,
    module.mongodb,
    module.redis,
  ]
}
