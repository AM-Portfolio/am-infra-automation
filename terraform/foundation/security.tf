# 1.5. KUBERNETES SECRETS STORE CSI DRIVER
module "csi_driver" {
  source = "../modules/core/csi-driver"
}

# 1.6. ZERO-TRUST NETWORK POLICIES
module "security_policies" {
  source = "../modules/core/security-policies"
  namespaces = [
    module.namespaces_core.infra_ns,
    module.namespaces_core.identity_ns,
    module.namespaces_core.monitoring_ns,
    module.namespaces_core.vault_ns
  ]
}
