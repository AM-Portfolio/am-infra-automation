output "kubeapi_hostname" {
  value = var.kubeapi_hostname
}

output "kubeapi_server_url" {
  value = var.kubeapi_server_url
}

output "dns_fqdn" {
  value = try("${cloudflare_record.kubeapi[0].name}.${var.root_domain}", var.kubeapi_hostname)
}

output "argo_cluster_secret_name" {
  value = var.argo_cluster_secret_name
}

output "argo_patch_applied" {
  value = local.do_patch
}

output "edge_extra_origin_hint" {
  description = "Pass this map into modules/core/edge var.extra_origin_ingress so tunnel routes kubeapi → Kind API."
  value = {
    (var.kubeapi_hostname) = "SET_KIND_API_ORIGIN" # consumer replaces with https://<kind-node>:6443
  }
}
