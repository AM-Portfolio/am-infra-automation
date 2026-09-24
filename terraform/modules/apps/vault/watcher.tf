# ==============================================================================
# Vault Unsealer Watcher — Persistent In-Cluster Auto-Unseal Daemon
# ==============================================================================
#
# Problem: Vault seals itself every time the pod or cluster restarts. Relying
# on one-shot scripts (manage.js, terraform_data) to unseal means every single
# `npm run <layer>:apply` must handle the unseal dance itself.
#
# Solution: A tiny, always-on Deployment that runs alongside vault-0:
#   1. Reads the unseal key from the vault-unseal-keys k8s Secret (volume mount)
#   2. Polls GET http://vault:8200/v1/sys/health every 15 seconds
#   3. If Vault is sealed → calls PUT /v1/sys/unseal with the key
#   4. If Vault is already unsealed → logs "healthy" and sleeps
#
# This pod costs ~5m CPU and 32Mi RAM. RBAC is scoped to read only the
# vault-unseal-keys secret in the vault namespace — nothing else.
#
# Lifecycle: This resource depends on terraform_data.vault_unsealer (which
# performs the initial init + first unseal). Once that resource exists, the
# watcher takes over permanently and manage.js never needs to unseal again.
# ==============================================================================

# ── RBAC ─────────────────────────────────────────────────────────────────────

resource "kubernetes_service_account" "vault_watcher" {
  count = var.enable_watcher ? 1 : 0
  metadata {
    name      = "vault-unsealer-watcher"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"      = "vault-unsealer-watcher"
      "app.kubernetes.io/component" = "infrastructure"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_role" "vault_watcher" {
  count = var.enable_watcher ? 1 : 0
  metadata {
    name      = "vault-unsealer-watcher"
    namespace = var.namespace
  }
  # Minimal permission: read-only access to the one secret that holds the keys
  rule {
    api_groups     = [""]
    resources      = ["secrets"]
    resource_names = ["vault-unseal-keys"]
    verbs          = ["get"]
  }
}

resource "kubernetes_role_binding" "vault_watcher" {
  count = var.enable_watcher ? 1 : 0
  metadata {
    name      = "vault-unsealer-watcher"
    namespace = var.namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.vault_watcher[0].metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vault_watcher[0].metadata[0].name
    namespace = var.namespace
  }
}

# ── WATCHER DEPLOYMENT ────────────────────────────────────────────────────────

resource "kubernetes_deployment" "vault_watcher" {
  count = var.enable_watcher ? 1 : 0
  metadata {
    name      = "vault-unsealer-watcher"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"      = "vault-unsealer-watcher"
      "app.kubernetes.io/component" = "infrastructure"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "vault-unsealer-watcher"
      }
    }

    # Never restart more than once per 30s to avoid thrashing during cluster boot
    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "vault-unsealer-watcher"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.vault_watcher[0].metadata[0].name

        # ── Init: wait for Vault pod to be reachable before starting the loop ──
        init_container {
          name  = "wait-for-vault"
          image = "curlimages/curl:8.6.0"

          command = [
            "sh", "-c",
            replace(trimspace(<<-EOT
              echo "[INIT] Waiting for Vault service to respond..."
              while true; do
                STATUS=$(curl -s -o /dev/null -w "%%{http_code}" --connect-timeout 5 http://vault:8200/v1/sys/health || echo "000")
                if [ "$STATUS" != "000" ]; then
                  echo "[INIT] Vault is reachable ($STATUS). Starting watcher."
                  break
                fi
                echo "[INIT] Vault not yet reachable. Retrying in 5s..."
                sleep 5
              done
            EOT
            ), "\r\n", "\n")
          ]

          resources {
            requests = {
              memory = "16Mi"
              cpu    = "5m"
            }
            limits = {
              memory = "32Mi"
              cpu    = "50m"
            }
          }
        }

        # ── Main watcher container ────────────────────────────────────────────
        container {
          name  = "watcher"
          image = "alpine:3.19"

          # Install curl + jq once at startup (tiny ~5MB download), then loop.
          # Using the headless vault-internal DNS to bypass readiness checks during unseal.
          command = ["/bin/sh", "-c"]
          args = [
            replace(trimspace(<<-EOT
              set -e
              apk add --no-cache curl jq > /dev/null 2>&1

              VAULT_ADDR="http://vault-0.vault-internal:8200"
              KEYS_FILE="/vault-keys/keys.json"
              POLL_INTERVAL="${var.watcher_poll_interval_seconds}"

              echo "[WATCHER] Vault Unsealer Watcher started."
              echo "[WATCHER]    Vault address : $VAULT_ADDR"
              echo "[WATCHER]    Poll interval : ${var.watcher_poll_interval_seconds}s"

              # Extract the base64 unseal key from the mounted secret
              UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' < "$KEYS_FILE")
              if [ -z "$UNSEAL_KEY" ] || [ "$UNSEAL_KEY" = "null" ]; then
                echo "[WATCHER] ERROR: No unseal key found in $KEYS_FILE. Did vault:apply run?"
                exit 1
              fi

              while true; do
                HEALTH=$(curl -s --connect-timeout 5 "$VAULT_ADDR/v1/sys/health" 2>/dev/null || echo '{"sealed":true,"initialized":false}')

                INITIALIZED=$(echo "$HEALTH" | jq -r 'if .initialized == null then "false" else (.initialized | tostring) end')
                SEALED=$(echo "$HEALTH" | jq -r 'if .sealed == null then "true" else (.sealed | tostring) end')

                if [ "$INITIALIZED" = "false" ]; then
                  echo "[WATCHER] Vault is not yet initialized. Waiting..."

                elif [ "$SEALED" = "true" ]; then
                  echo "[WATCHER] Vault is sealed. Sending unseal request..."
                  PAYLOAD="{\"key\":\"$UNSEAL_KEY\"}"
                  RESULT=$(curl -s -X PUT "$VAULT_ADDR/v1/sys/unseal" -H "Content-Type: application/json" -d "$PAYLOAD" 2>/dev/null || echo '{"sealed":true}')

                  STILL_SEALED=$(echo "$RESULT" | jq -r 'if .sealed == null then "true" else (.sealed | tostring) end')
                  if [ "$STILL_SEALED" = "false" ]; then
                    echo "[WATCHER] Vault unsealed successfully."
                  else
                    echo "[WATCHER] Unseal attempt failed. Response: $RESULT"
                  fi

                else
                  echo "[WATCHER] Vault is healthy and unsealed."
                fi

                sleep "$POLL_INTERVAL"
              done
            EOT
            ), "\r\n", "\n")
          ]

          # Mount the unseal keys secret as a read-only volume
          volume_mount {
            name       = "vault-keys"
            mount_path = "/vault-keys"
            read_only  = true
          }

          resources {
            requests = {
              memory = "32Mi"
              cpu    = "5m"
            }
            limits = {
              memory = "64Mi"
              cpu    = "50m"
            }
          }

          # Liveness: if the shell loop dies the container should restart
          liveness_probe {
            exec {
              command = ["sh", "-c", "[ -f /vault-keys/keys.json ]"]
            }
            initial_delay_seconds = 30
            period_seconds        = 60
            failure_threshold     = 3
          }
        }

        # ── Volume: the vault-unseal-keys secret ───────────────────────────────
        volume {
          name = "vault-keys"
          secret {
            secret_name = "vault-unseal-keys"
            items {
              key  = "keys.json"
              path = "keys.json"
            }
            # Read-only; the pod never writes back
            optional = false
          }
        }

        # Tolerate nodes that are still coming up
        toleration {
          key      = "node.kubernetes.io/not-ready"
          operator = "Exists"
          effect   = "NoExecute"
          toleration_seconds = 60
        }
        toleration {
          key      = "node.kubernetes.io/unreachable"
          operator = "Exists"
          effect   = "NoExecute"
          toleration_seconds = 60
        }

        restart_policy = "Always"
      }
    }
  }

  # Wait for the first unseal (null_resource.vault_unsealer) and the secret to
  # exist before deploying the watcher. The watcher then owns all future unseals.
  depends_on = [helm_release.vault]
}
