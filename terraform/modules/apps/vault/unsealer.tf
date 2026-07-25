# ==============================================================================
# Vault Auto-Unsealer Logic (Idempotent Refactor)
# ==============================================================================
# This implementation uses terraform_data with a local-exec provisioner.
# Why? Because kubernetes_job causes conflicts if the job already exists.
# terraform_data ensures the unseal logic runs whenever the Helm chart changes
# but doesn't leave brittle batch objects in the Kubernetes API.
# ==============================================================================

resource "null_resource" "vault_unsealer" {
  triggers = {
    timestamp = timestamp()
  }

  provisioner "local-exec" {
    command = <<EOT
      # Resolve Kubeconfig path dynamically
      KUBECONFIG_PATH="${var.kubeconfig_path}"
      if [ -z "$KUBECONFIG_PATH" ]; then
        if [ "${var.environment}" = "local" ]; then
          KUBECONFIG_PATH="$HOME/.kube/config"
        else
          KUBECONFIG_PATH="/data/am-state/am-${var.environment}-config"
        fi
      fi

      echo "🔐 [BOOTSTRAP] Waiting for Vault to be responsive on K8s cluster..."
      STATUS_JSON=""
      for i in {1..45}; do
        STATUS_JSON=$(kubectl --kubeconfig="$KUBECONFIG_PATH" exec -n vault vault-0 -- env VAULT_ADDR=http://127.0.0.1:8200 vault status -format=json 2>/dev/null || true)
        if [ -n "$STATUS_JSON" ]; then
          echo "✅ vault-0 is responsive."
          break
        fi
        echo "⏳ vault-0 is not responsive yet (waiting 10s...)"
        sleep 10
      done

      if [ -z "$STATUS_JSON" ]; then
        echo "❌ Timeout waiting for vault-0 to respond."
        exit 1
      fi

      INITIALIZED=$(echo "$STATUS_JSON" | grep -o '"initialized":[^,]*' | cut -d: -f2 | tr -d ' "')
      SEALED=$(echo "$STATUS_JSON" | grep -o '"sealed":[^,]*' | cut -d: -f2 | tr -d ' "')

      if [ "$INITIALIZED" = "false" ]; then
        echo "🚀 [INIT] Vault is uninitialized. Starting auto-initialization..."
        INIT_JSON=$(kubectl --kubeconfig="$KUBECONFIG_PATH" exec -n vault vault-0 -- env VAULT_ADDR=http://127.0.0.1:8200 vault operator init -key-shares=1 -key-threshold=1 -format=json)
        
        if [ -n "$INIT_JSON" ]; then
          echo "✅ Vault successfully initialized."
          
          # Extract keys
          UNSEAL_KEY=$(echo "$INIT_JSON" | grep -o '"unseal_keys_b64":\["[^"]*"' | cut -d'"' -f4)
          
          # Save to local workspace keys.json
          echo "$INIT_JSON" > ../../../keys.json
          echo "💾 Keys backed up to keys.json"
          
          # Create vault-unseal-keys secret in K8s
          kubectl --kubeconfig="$KUBECONFIG_PATH" create secret generic vault-unseal-keys -n vault --from-literal=keys.json="$INIT_JSON" --dry-run=client -o yaml | kubectl --kubeconfig="$KUBECONFIG_PATH" apply -f -
          echo "🔑 Kubernetes secret vault-unseal-keys created."
          
          # Perform first unseal
          kubectl --kubeconfig="$KUBECONFIG_PATH" exec -n vault vault-0 -- env VAULT_ADDR=http://127.0.0.1:8200 vault operator unseal "$UNSEAL_KEY"
          echo "🔓 Vault unsealed."
        else
          echo "❌ Failed to initialize Vault."
          exit 1
        fi
      elif [ "$INITIALIZED" = "true" ] && [ "$SEALED" = "true" ]; then
        echo "🔓 Vault is initialized but sealed. Unsealing now..."
        kubectl --kubeconfig="$KUBECONFIG_PATH" exec -n vault vault-0 -- env VAULT_ADDR=http://127.0.0.1:8200 vault operator unseal "${var.vault_unseal_key}"
        echo "✅ Vault Unsealed."
      elif [ "$INITIALIZED" = "true" ] && [ "$SEALED" = "false" ]; then
        echo "✅ Vault is already initialized and unsealed."
      else
        echo "⚠️ Unable to determine Vault status: $STATUS_JSON"
      fi
    EOT

    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [helm_release.vault]
}
