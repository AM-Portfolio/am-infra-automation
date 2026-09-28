# Patch existing Argo cluster secret server field only.
# No destroy provisioner — removing this resource must NOT delete the Secret.

locals {
  do_patch = var.enabled && var.enable_argo_patch && var.argo_kubeconfig != ""
}

resource "null_resource" "argo_cluster_server_patch" {
  count = local.do_patch ? 1 : 0

  triggers = {
    secret_name = var.argo_cluster_secret_name
    namespace   = var.argo_namespace
    server_url  = var.kubeapi_server_url
    kubeconfig  = var.argo_kubeconfig
    context     = var.argo_kube_context
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      KUBECONFIG  = var.argo_kubeconfig
      SECRET      = var.argo_cluster_secret_name
      NS          = var.argo_namespace
      SERVER_URL  = var.kubeapi_server_url
      EXTRA_CTX   = var.argo_kube_context
    }
    command = <<-EOT
      set -euo pipefail
      CTX_ARGS=()
      if [ -n "$${EXTRA_CTX}" ]; then CTX_ARGS=(--context "$${EXTRA_CTX}"); fi
      # Ensure secret exists — never create/replace; fail closed if missing
      kubectl --kubeconfig "$${KUBECONFIG}" "$${CTX_ARGS[@]}" -n "$${NS}" get secret "$${SECRET}" >/dev/null
      # Patch only the server key (base64). Leave config/token/CA untouched.
      B64=$(printf '%s' "$${SERVER_URL}" | base64 | tr -d '\n')
      kubectl --kubeconfig "$${KUBECONFIG}" "$${CTX_ARGS[@]}" -n "$${NS}" patch secret "$${SECRET}" \
        --type merge \
        -p "{\"data\":{\"server\":\"$${B64}\"}}"
      echo "patched $${SECRET} server=$${SERVER_URL}"
    EOT
  }

  depends_on = [terraform_data.server_url_guard]
}
