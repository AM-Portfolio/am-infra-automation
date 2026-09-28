output "zone_id" {
  value = data.cloudflare_zone.main.id
}

output "monitor_ids" {
  value = local.monitor_ids
}

output "dr_pool_ids" {
  value = { for k, p in cloudflare_load_balancer_pool.dr : k => p.id }
}

output "prod_pool_ids" {
  value = { for k, p in cloudflare_load_balancer_pool.prod : k => p.id }
}

output "load_balancer_hosts" {
  value = [for k, lb in cloudflare_load_balancer.host : lb.name]
}

output "dr_pool_enabled" {
  value = var.dr_pool_enabled
}

output "restore_dr_primary_hint" {
  value = "After Contabo fallback: set dr_pool_enabled=false until soak; to restore DR primary set true and terraform apply after verifying DR + G20 writer."
}
