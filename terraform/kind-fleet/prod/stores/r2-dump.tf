# Optional continuous dump → R2 (identity-infra-split Phase 5).
# Enable with enable_r2_dump=true and CF token vars (see terraform.tfvars.r2-dump.example).

variable "enable_r2_dump" {
  type    = bool
  default = false
}

variable "r2_dump_cloudflare_account_id" {
  type      = string
  default   = ""
  sensitive = true
}

variable "r2_dump_cloudflare_api_token" {
  type      = string
  default   = ""
  sensitive = true
}

variable "r2_dump_cloudflare_email" {
  type      = string
  default   = ""
  sensitive = true
}

variable "r2_dump_cloudflare_api_key" {
  type      = string
  default   = ""
  sensitive = true
}

module "r2_db_dump" {
  source    = "../../../modules/core/r2-db-dump"
  enabled   = var.enable_r2_dump
  namespace = module.namespaces.infra_ns
  schedule  = "0 */6 * * *"
  r2_bucket = "asrax-disaster"
  prefix    = "prod"

  cloudflare_account_id = var.r2_dump_cloudflare_account_id
  cloudflare_api_token  = var.r2_dump_cloudflare_api_token
  cloudflare_email      = var.r2_dump_cloudflare_email
  cloudflare_api_key    = var.r2_dump_cloudflare_api_key
  redis_password        = random_password.redis.result

  depends_on = [
    module.postgresql,
    module.mongodb,
    module.redis,
  ]
}
