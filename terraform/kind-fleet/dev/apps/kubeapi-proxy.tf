# Contabo Argo → dig Kind API via Cloudflare Tunnel (covers dig + preprod apps on am-dev-apps).
module "kubeapi_proxy" {
  source    = "../../../modules/ops/kubeapi-proxy"
  namespace = "infra"
}

output "kubeapi_proxy_origin" {
  value       = module.kubeapi_proxy.origin_url
  description = "Set dig/edge kubeapi_kind_api_origin to this value."
}
