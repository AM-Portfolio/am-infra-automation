# Product UI hosts → apps Traefik (NodePort 30080) via infra Traefik.
# Replaces ad-hoc scripts/kind-fleet/_apps_bridge_hosts.yaml.

data "external" "apps_node_ip" {
  program = ["bash", "${path.module}/../apps/scripts/apps-cp-ip.sh"]
}

module "apps_traefik_bridge" {
  source = "../../../modules/core/apps-traefik-bridge"
  providers = {
    kubernetes = kubernetes.infra
    kubectl    = kubectl.infra
  }
  namespace     = "infra"
  service_name = "apps-traefik-bridge"
  service_port = 80
  backend_host = "am-${local.env}-apps-control-plane"
  backend_ip   = try(data.external.apps_node_ip.result.ip, "")
  backend_port = 30080
  host_fqdns = [
    "am.${local.domain}",
    "asrax.${local.domain}",
    "corp.${local.domain}",
    local.domain, # apex asrax.in
  ]
}

output "apps_traefik_bridge_ip" {
  value = module.apps_traefik_bridge.backend_ip
}
