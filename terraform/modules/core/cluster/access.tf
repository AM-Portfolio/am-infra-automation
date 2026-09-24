# ==============================================================================
# CLUSTER ACCESS — optional kubeconfig write (skipped when path is empty)
# ==============================================================================

resource "null_resource" "cluster_automation" {
  count = var.config_output_path != "" ? 1 : 0

  triggers = {
    cluster_id = kind_cluster.this.id
    port       = tostring(local.api_server_port)
    name       = local.cluster_name
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "until docker exec ${local.cluster_name}-control-plane kubectl get nodes --kubeconfig /etc/kubernetes/admin.conf &>/dev/null; do sleep 2; done; docker exec ${local.cluster_name}-control-plane cat /etc/kubernetes/admin.conf > \"${var.config_output_path}.tmp\"; perl -pi -e \"s|https://.*:${local.api_server_port}|https://127.0.0.1:${local.api_server_port}|g\" \"${var.config_output_path}.tmp\"; docker exec ${local.cluster_name}-control-plane kubectl create serviceaccount am-admin -n kube-system --kubeconfig /etc/kubernetes/admin.conf || true; docker exec ${local.cluster_name}-control-plane kubectl create clusterrolebinding am-admin-binding --clusterrole=cluster-admin --serviceaccount=kube-system:am-admin --kubeconfig /etc/kubernetes/admin.conf || true; TOKEN=$(docker exec ${local.cluster_name}-control-plane kubectl create token am-admin -n kube-system --duration=24h --kubeconfig /etc/kubernetes/admin.conf); printf \"apiVersion: v1\\nkind: Config\\nclusters:\\n- cluster:\\n    server: https://127.0.0.1:${local.api_server_port}\\n    insecure-skip-tls-verify: true\\n  name: kind-${local.cluster_name}\\ncontexts:\\n- context:\\n    cluster: kind-${local.cluster_name}\\n    user: am-admin\\n  name: kind-${local.cluster_name}\\ncurrent-context: kind-${local.cluster_name}\\nusers:\\n- name: am-admin\\n  user:\\n    token: $TOKEN\\n\" > \"${var.config_output_path}\"; docker exec ${local.cluster_name}-control-plane kubectl taint nodes ${local.cluster_name}-control-plane node-role.kubernetes.io/control-plane:NoSchedule- --kubeconfig /etc/kubernetes/admin.conf || true; echo 'Automation Complete'"
  }

  depends_on = [kind_cluster.this]
}
