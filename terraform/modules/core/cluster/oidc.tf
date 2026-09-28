# Apply OIDC RBAC when apiserver OIDC is configured (iam-sso Phase 3).

resource "null_resource" "oidc_rbac" {
  count = var.oidc_issuer_url != "" ? 1 : 0

  triggers = {
    issuer = var.oidc_issuer_url
    client = var.oidc_client_id
    rbac   = filesha256("${path.module}/oidc-rbac.yaml")
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      KUBECONFIG = var.config_output_path != "" ? var.config_output_path : ""
      CLUSTER    = local.cluster_name
      RBAC_FILE  = "${path.module}/oidc-rbac.yaml"
    }
    command = <<-BASH
      set -euo pipefail
      KCFG="$${KUBECONFIG}"
      if [ -z "$KCFG" ] || [ ! -f "$KCFG" ]; then
        KCFG="$HOME/.asrax/kubeconfig.$${CLUSTER}.yaml"
      fi
      if [ ! -f "$KCFG" ]; then
        echo "oidc_rbac_skip_no_kubeconfig"
        exit 0
      fi
      kubectl --kubeconfig "$KCFG" apply -f "$RBAC_FILE"
      echo oidc_rbac_applied
    BASH
  }

  depends_on = [kind_cluster.this]
}

# Patch running apiserver for OIDC on existing clusters (kind_config only applies on create).
resource "null_resource" "oidc_apiserver_patch" {
  count = var.oidc_issuer_url != "" ? 1 : 0

  triggers = {
    issuer = var.oidc_issuer_url
    client = var.oidc_client_id
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      NODE   = "${local.cluster_name}-control-plane"
      ISSUER = var.oidc_issuer_url
      CLIENT = var.oidc_client_id
    }
    command = <<-BASH
      set -euo pipefail
      if ! docker inspect "$NODE" >/dev/null 2>&1; then
        echo oidc_patch_skip_no_node
        exit 0
      fi
      docker exec "$NODE" bash -c "
        set -e
        f=/etc/kubernetes/manifests/kube-apiserver.yaml
        grep -q 'oidc-issuer-url' \"\$f\" && exit 0
        sed -i '/- kube-apiserver/a\\    - --oidc-issuer-url=${ISSUER}\\n    - --oidc-client-id=${CLIENT}\\n    - --oidc-username-claim=email\\n    - --oidc-groups-claim=groups' \"\$f\"
      "
      echo oidc_apiserver_patched
    BASH
  }

  depends_on = [kind_cluster.this]
}
