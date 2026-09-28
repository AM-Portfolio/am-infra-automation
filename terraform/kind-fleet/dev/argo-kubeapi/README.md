# dig / nonprod-dr — kubeapi-dev.asrax.in
#
# Phase 0: probe DNS/TCP:443 and GET /version before enable_argo_patch.
# Pair with kind-fleet/dev/edge extra_origin_ingress (wired via kubeapi_kind_api_origin).
#
# ```bash
# cd terraform/kind-fleet/dev/argo-kubeapi
# terraform init
# terraform plan -var='tunnel_id=…' -var='cloudflare_api_token=…' -var='cloudflare_account_id=…'
# terraform apply ...   # DNS only while enable_argo_patch=false
# # After DNS resolves and Kind API reachable via tunnel:
# terraform apply -var='enable_argo_patch=true' -var='argo_kubeconfig=/path/to/contabo-argo.kubeconfig'
# ```
#
# Does not delete Argo secrets, tunnels, or kind-api-proxy.
