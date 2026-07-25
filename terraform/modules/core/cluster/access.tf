# ==============================================================================
# CLUSTER ACCESS — Robust Phased Automation
# ==============================================================================

# 1. Automated Admin Access & Config Generation
resource "null_resource" "cluster_automation" {
  count = var.config_output_path != "" ? 1 : 0

  # Trigger this whenever the cluster is recreated
  triggers = {
    cluster_id = kind_cluster.this.id
    manual_run = "force-v5"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "until docker exec ${var.cluster_name}-control-plane kubectl get nodes --kubeconfig /etc/kubernetes/admin.conf &>/dev/null; do sleep 2; done; docker exec ${var.cluster_name}-control-plane cat /etc/kubernetes/admin.conf > \"${var.config_output_path}.tmp\"; perl -pi -e \"s|https://.*:6443|https://127.0.0.1:6443|g\" \"${var.config_output_path}.tmp\"; docker exec ${var.cluster_name}-control-plane kubectl create serviceaccount am-admin -n kube-system --kubeconfig /etc/kubernetes/admin.conf || true; docker exec ${var.cluster_name}-control-plane kubectl create clusterrolebinding am-admin-binding --clusterrole=cluster-admin --serviceaccount=kube-system:am-admin --kubeconfig /etc/kubernetes/admin.conf || true; TOKEN=$(docker exec ${var.cluster_name}-control-plane kubectl create token am-admin -n kube-system --duration=24h --kubeconfig /etc/kubernetes/admin.conf); printf \"apiVersion: v1\\nkind: Config\\nclusters:\\n- cluster:\\n    server: https://127.0.0.1:6443\\n    insecure-skip-tls-verify: true\\n  name: kind-${var.cluster_name}\\ncontexts:\\n- context:\\n    cluster: kind-${var.cluster_name}\\n    user: am-admin\\n  name: kind-${var.cluster_name}\\ncurrent-context: kind-${var.cluster_name}\\nusers:\\n- name: am-admin\\n  user:\\n    token: $TOKEN\\n\" > \"${var.config_output_path}\"; docker exec ${var.cluster_name}-control-plane kubectl taint nodes ${var.cluster_name}-control-plane node-role.kubernetes.io/control-plane:NoSchedule- --kubeconfig /etc/kubernetes/admin.conf || true; echo '✅ Automation Complete!'"
  }

  depends_on = [kind_cluster.this]
}
