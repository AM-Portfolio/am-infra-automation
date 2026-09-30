# Contabo DR Argo → DR Kind API via Cloudflare Tunnel.
module "kubeapi_proxy" {
  source    = "../../../modules/ops/kubeapi-proxy"
  namespace = "infra"
}

output "kubeapi_proxy_origin" {
  value = module.kubeapi_proxy.origin_url
}
