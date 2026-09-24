# Host-port bridge for DNS-only store names. Not kubectl port-forward (G27).
# VPS Phase 2: targets Docker DNS am-prod-infra-control-plane (never bake Kind IP).
# Apply on the VPS only — do not apply this folder on the laptop.

locals {
  env       = "prod"
  kind_node = "am-${local.env}-infra-control-plane"
  mappings_ports = [
    { name = "postgres", host_port = 5432, target_port = 30432 },
    { name = "mongo", host_port = 27017, target_port = 30017 },
    { name = "redis", host_port = 6379, target_port = 30379 },
    { name = "kafka", host_port = 9092, target_port = 30092 },
    { name = "influx", host_port = 8086, target_port = 30806 },
    { name = "minio", host_port = 9000, target_port = 30900 },
    { name = "vault", host_port = 8200, target_port = 30820 },
  ]
  docker_ports = join(" ", [for m in local.mappings_ports : "-p ${m.host_port}:${m.host_port}"])
}

resource "null_resource" "port_exposer" {
  triggers = {
    mappings  = jsonencode(local.mappings_ports)
    kind_node = local.kind_node
    version   = "3-docker-dns-hostname"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-BASH
      set -euo pipefail
      NODE='${local.kind_node}'
      for i in $(seq 1 40); do
        if docker inspect "$NODE" >/dev/null 2>&1; then break; fi
        sleep 3
      done
      docker inspect "$NODE" >/dev/null 2>&1 || { echo "$NODE not found"; exit 1; }
      echo "kind_node=$NODE (Docker DNS; IP may change after restart)"
      INNER="socat TCP-LISTEN:5432,fork,reuseaddr TCP:$${NODE}:30432 & socat TCP-LISTEN:27017,fork,reuseaddr TCP:$${NODE}:30017 & socat TCP-LISTEN:6379,fork,reuseaddr TCP:$${NODE}:30379 & socat TCP-LISTEN:9092,fork,reuseaddr TCP:$${NODE}:30092 & socat TCP-LISTEN:8086,fork,reuseaddr TCP:$${NODE}:30806 & socat TCP-LISTEN:9000,fork,reuseaddr TCP:$${NODE}:30900 & socat TCP-LISTEN:8200,fork,reuseaddr TCP:$${NODE}:30820 & wait"
      docker rm -f am-port-exposer 2>/dev/null || true
      docker run -d --name am-port-exposer ${local.docker_ports} --network kind --restart always --entrypoint /bin/sh alpine/socat -c "$INNER"
      sleep 3
      test "$(docker inspect -f '{{.State.Running}}' am-port-exposer)" = "true"
      echo "am-port-exposer up targeting $NODE"
    BASH
  }

  provisioner "local-exec" {
    when    = destroy
    command = "docker rm -f am-port-exposer 2>/dev/null || true"
  }
}

output "kind_node_dns" { value = local.kind_node }
output "mappings_ports" { value = local.mappings_ports }
output "host_private_ip_note" {
  value = "Cloudflare DNS-only A for postgres|mongo|redis|kafka.asrax.in must be the VPS private/WG IP (not localhost, not Docker 172.19)."
}
