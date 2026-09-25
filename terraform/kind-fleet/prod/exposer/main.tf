# Host-port bridge for DNS-only store names. Not kubectl port-forward (G27).
# VPS Phase 2: targets Docker DNS am-prod-infra-worker (never bake Kind IP).
# CP NodePort :30017 (mongo) timed out from kind network; worker NodePorts OK.
# Apply on the VPS only — do not apply this folder on the laptop.

locals {
  env       = "prod"
  domain    = "asrax.in"
  # Worker: CP NodePort :30017 (mongo) times out from kind network; worker OK for all store NodePorts.
  kind_node = "am-${local.env}-infra-worker"
  mappings_ports = [
    { name = "postgres", host_port = 5432, target_port = 30432 },
    { name = "mongo", host_port = 27017, target_port = 30017 },
    { name = "redis", host_port = 6379, target_port = 30379 },
    { name = "kafka", host_port = 9092, target_port = 30092 },
    { name = "influx", host_port = 8086, target_port = 30806 },
    { name = "minio", host_port = 9000, target_port = 30900 },
    { name = "vault", host_port = 8200, target_port = 30820 },
  ]
  # Temporal gRPC on platform CP NodePort (not infra-worker).
  temporal_node      = "am-${local.env}-platform-control-plane"
  temporal_host_port = 7233
  temporal_node_port = 30723
  # Split-horizon: kind-network pods resolve bare TCP store FQDNs to exposer (public A hairpins fail).
  # Do NOT alias vault/influx HTTPS names — those must stay CF-proxied (443). Exposer only bridges TCP :8200/:8086.
  # Apps/env/Vault often use mongodb.asrax.in while mapping name is "mongo" — alias both.
  store_aliases = distinct(concat(
    [
      for m in local.mappings_ports : "${m.name}.${local.domain}"
      if !contains(["vault", "influx"], m.name)
    ],
    ["mongodb.${local.domain}"],
  ))
  docker_ports = join(" ", concat(
    [for m in local.mappings_ports : "-p ${m.host_port}:${m.host_port}"],
    ["-p ${local.temporal_host_port}:${local.temporal_host_port}"],
  ))
  docker_aliases = join(" ", [for a in local.store_aliases : "--network-alias ${a}"])
}

resource "null_resource" "port_exposer" {
  triggers = {
    mappings       = jsonencode(local.mappings_ports)
    kind_node      = local.kind_node
    aliases        = jsonencode(local.store_aliases)
    temporal_node  = local.temporal_node
    temporal_ports = "${local.temporal_host_port}:${local.temporal_node_port}"
    # v8: Temporal gRPC :7233 → platform CP :30723
    version = "8-temporal-grpc"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-BASH
      set -euo pipefail
      NODE='${local.kind_node}'
      TNODE='${local.temporal_node}'
      for i in $(seq 1 40); do
        if docker inspect "$NODE" >/dev/null 2>&1 && docker inspect "$TNODE" >/dev/null 2>&1; then break; fi
        sleep 3
      done
      docker inspect "$NODE" >/dev/null 2>&1 || { echo "$NODE not found"; exit 1; }
      docker inspect "$TNODE" >/dev/null 2>&1 || { echo "$TNODE not found"; exit 1; }
      echo "kind_node=$NODE temporal_node=$TNODE"
      INNER="socat TCP4-LISTEN:5432,fork,reuseaddr TCP4:$${NODE}:30432 & socat TCP4-LISTEN:27017,fork,reuseaddr TCP4:$${NODE}:30017 & socat TCP4-LISTEN:6379,fork,reuseaddr TCP4:$${NODE}:30379 & socat TCP4-LISTEN:9092,fork,reuseaddr TCP4:$${NODE}:30092 & socat TCP4-LISTEN:8086,fork,reuseaddr TCP4:$${NODE}:30806 & socat TCP4-LISTEN:9000,fork,reuseaddr TCP4:$${NODE}:30900 & socat TCP4-LISTEN:8200,fork,reuseaddr TCP4:$${NODE}:30820 & socat TCP4-LISTEN:${local.temporal_host_port},fork,reuseaddr TCP4:$${TNODE}:${local.temporal_node_port} & wait"
      docker rm -f am-port-exposer 2>/dev/null || true
      docker run -d --name am-port-exposer ${local.docker_ports} --network kind ${local.docker_aliases} --restart always --entrypoint /bin/sh alpine/socat -c "$INNER"
      sleep 3
      test "$(docker inspect -f '{{.State.Running}}' am-port-exposer)" = "true"
      echo "am-port-exposer up targeting $NODE + temporal $TNODE:${local.temporal_node_port} aliases=${join(",", local.store_aliases)}"
    BASH
  }

  provisioner "local-exec" {
    when    = destroy
    command = "docker rm -f am-port-exposer 2>/dev/null || true"
  }
}

output "kind_node_dns" { value = local.kind_node }
output "mappings_ports" { value = local.mappings_ports }
output "temporal_mapping" {
  value = "${local.temporal_host_port} → ${local.temporal_node}:${local.temporal_node_port}"
}
output "host_private_ip_note" {
  value = "Cloudflare DNS-only A for postgres|mongo|redis|kafka.asrax.in must be the VPS private/WG IP (not localhost, not Docker 172.19)."
}
