# preprod — kubeapi-preprod.asrax.in → cluster-am-vps-nonprod
#
# No kind-fleet/preprod/edge yet; after DNS apply, merge edge_extra_origin_ingress
# into Contabo nonprod tunnel config (or future edge stack) before enable_argo_patch.
#
# ```bash
# cd terraform/kind-fleet/preprod/argo-kubeapi
# terraform init && terraform plan
# ```
