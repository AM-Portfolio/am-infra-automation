# ------------------------------------------------------------------------------
# Vault Helm Deployment
# ------------------------------------------------------------------------------

# Note: Manual PVs removed in favor of standard dynamic provisioning (Docker Volumes)
# which is more stable for local Kind/Windows development and supports chown/UID 100.

resource "helm_release" "vault" {
  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  namespace  = var.namespace
  version    = "0.27.0"

  values = [yamlencode({
    server = {
      nodeSelector = {
        role = "infra"
      }
      ha = { enabled = false }
      standalone = { enabled = true }
      service = merge(
        {
          enabled = true
          type    = var.service_type
        },
        var.service_type == "NodePort" ? { nodePort = var.vault_node_port } : {}
      )
      resources = {
        requests = { memory = var.memory_request, cpu = var.cpu_request }
        limits   = { memory = var.memory_limit, cpu = var.cpu_limit }
      }
      readinessProbe = {
        enabled        = true
        timeoutSeconds = 10
      }
      livenessProbe = {
        enabled        = true
        timeoutSeconds = 10
      }
      dataStorage = {
        enabled      = true
        size         = "2Gi"
        # Using default 'standard' class for resilient Docker Volumes
        storageClass = "standard" 
      }
      auditStorage = {
        enabled      = true
        size         = "1Gi"
        storageClass = "standard"
      }
      dev = { enabled = false }
      hostAliases = var.enable_host_aliases ? [
        {
          ip        = "10.96.208.223"
          hostnames = ["authentik.${var.root_domain}"]
        }
      ] : []
    }
    ui = {
      enabled     = true
      serviceType = var.ui_service_type
    }
    injector = {
      enabled = var.injector_enabled
    }
    csi = {
      enabled = var.csi_enabled
    }
  })]

  # set 'wait = false' to break circular dependency with unseal script
  wait = false

  # ==============================================================================
  # ENTERPRISE PREVENTION LOCK: Do NOT delete the Vault instance accidentally
  # ==============================================================================
  lifecycle {
    prevent_destroy = true
  }
}
