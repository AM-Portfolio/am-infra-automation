from pathlib import Path
import re

p = Path(r"f:\am-repos\am-repos\am-infra-automation\terraform\kind-fleet\dr\platform\main.tf")
text = p.read_text(encoding="utf-8").replace("\r\n", "\n")

old_header = """# Phase 3a–3d platform (dr): Keycloak + Argo + Temporal + Lago + P1 UIs.
# Traefik stays on infra; cross-cluster-http bridges published *-dr hosts.
# Apply on VPS3 only. State: /data/am-state/terraform/dr/platform/
"""
new_header = """# Phase 3a–3d platform (dr): Keycloak + Argo + Temporal + Lago + P1 UIs.
# identity-infra-split Phase 6: set co_locate_on_infra=true → am-dr-infra (no platform Kind).
# Default false keeps am-dr-platform :6445 until soak apply.
# Apply on VPS3 only. State: /data/am-state/terraform/dr/platform/
"""
if old_header not in text:
    raise SystemExit("header mismatch")
text = text.replace(old_header, new_header, 1)

old_cluster = """module \"cluster\" {
  source             = \"../../../modules/core/cluster\"
  env                = local.env
  cluster_role       = \"platform\"
  node_shape         = \"one\"
  vps_ram_gb         = 32
  api_server_address = \"0.0.0.0\"
  vps_ip             = \"129.121.128.131\"
  config_output_path = \"/data/am-state/kubeconfig.am-dr-platform.yaml\"
}

resource \"null_resource\" \"kubeconfig_asrax\" {
  triggers = {
    cluster = module.cluster.cluster_name
    endpoint = module.cluster.endpoint
  }
  provisioner \"local-exec\" {
    command = \"mkdir -p /home/am-ops/.asrax && cp -f /data/am-state/kubeconfig.am-dr-platform.yaml /home/am-ops/.asrax/kubeconfig.am-dr-platform.yaml && chmod 600 /home/am-ops/.asrax/kubeconfig.am-dr-platform.yaml && chown am-ops:am-ops /home/am-ops/.asrax/kubeconfig.am-dr-platform.yaml || true\"
  }
  depends_on = [module.cluster]
}

data \"external\" \"platform_node_ip\" {
  program    = [\"bash\", \"${path.module}/scripts/platform-ip.sh\"]
  depends_on = [module.cluster]
}

locals {
  platform_ip = coalesce(var.platform_node_ip, try(data.external.platform_node_ip.result.ip, \"\"))
  # DR store hosts (Phase 2 exposer / DNS-only grey-cloud).
  pg_host    = \"postgres-dr.${local.domain}\"
  mongo_host = \"mongodb-dr.${local.domain}\"
  redis_host = \"redis-dr.${local.domain}\"
  minio_host = \"minio-dr.${local.domain}:9000\"
}

module \"namespaces\" {
  source            = \"../../../modules/core/namespaces\"
  environment       = local.env
  create_identity   = true
  create_apps       = false
  create_github     = false
  create_monitoring = false
  extra_namespaces  = [\"argocd\", \"temporal\", \"billing\", \"n8n\", \"growthbook\", \"openproject\", \"am-ai\", \"notification\"]

  depends_on = [module.cluster]
}

module \"image_preload_3d\" {
  source       = \"../../../modules/core/kind-image-preload\"
  cluster_name = module.cluster.cluster_name
"""

new_cluster = """module \"cluster\" {
  count              = local.co_locate_on_infra ? 0 : 1
  source             = \"../../../modules/core/cluster\"
  env                = local.env
  cluster_role       = \"platform\"
  node_shape         = \"one\"
  vps_ram_gb         = 32
  api_server_address = \"0.0.0.0\"
  vps_ip             = \"129.121.128.131\"
  config_output_path = \"/data/am-state/kubeconfig.am-dr-platform.yaml\"
}

resource \"null_resource\" \"kubeconfig_asrax\" {
  count = local.co_locate_on_infra ? 0 : 1
  triggers = {
    cluster  = module.cluster[0].cluster_name
    endpoint = module.cluster[0].endpoint
  }
  provisioner \"local-exec\" {
    command = \"mkdir -p /home/am-ops/.asrax && cp -f /data/am-state/kubeconfig.am-dr-platform.yaml /home/am-ops/.asrax/kubeconfig.am-dr-platform.yaml && chmod 600 /home/am-ops/.asrax/kubeconfig.am-dr-platform.yaml && chown am-ops:am-ops /home/am-ops/.asrax/kubeconfig.am-dr-platform.yaml || true\"
  }
  depends_on = [module.cluster]
}

data \"external\" \"platform_node_ip\" {
  count      = local.co_locate_on_infra ? 0 : 1
  program    = [\"bash\", \"${path.module}/scripts/platform-ip.sh\"]
  depends_on = [module.cluster]
}

resource \"terraform_data\" \"kind_ready\" {
  input = local.co_locate_on_infra ? \"am-dr-infra\" : module.cluster[0].cluster_name
}

locals {
  platform_ip = local.co_locate_on_infra ? \"\" : coalesce(var.platform_node_ip, try(data.external.platform_node_ip[0].result.ip, \"\"))
  kind_name   = local.co_locate_on_infra ? \"am-dr-infra\" : module.cluster[0].cluster_name
  # DR store hosts (Phase 2 exposer / DNS-only grey-cloud).
  pg_host    = \"postgres-dr.${local.domain}\"
  mongo_host = \"mongodb-dr.${local.domain}\"
  redis_host = \"redis-dr.${local.domain}\"
  minio_host = \"minio-dr.${local.domain}:9000\"
}

module \"namespaces\" {
  source            = \"../../../modules/core/namespaces\"
  environment       = local.env
  create_identity   = true
  create_apps       = false
  create_github     = false
  create_monitoring = false
  extra_namespaces  = [\"argocd\", \"temporal\", \"billing\", \"n8n\", \"growthbook\", \"openproject\", \"am-ai\", \"notification\"]

  depends_on = [terraform_data.kind_ready]
}

module \"image_preload_3d\" {
  source       = \"../../../modules/core/kind-image-preload\"
  cluster_name = local.kind_name
"""
if old_cluster not in text:
    raise SystemExit("cluster block mismatch")
text = text.replace(old_cluster, new_cluster, 1)

text = text.replace(
    """  depends_on = [module.cluster]
}

module \"keycloak\" {""",
    """  depends_on = [terraform_data.kind_ready]
}

module \"keycloak\" {""",
    1,
)

# gateway_same_cluster false → local
text = re.sub(
    r"gateway_same_cluster(\s*)=\s*false",
    r"gateway_same_cluster\1= local.gateway_same_cluster",
    text,
)

text = text.replace(
    '      KUBECONFIG = "/data/am-state/kubeconfig.am-dr-platform.yaml"',
    "      KUBECONFIG = local.workload_kubeconfig",
)

text, n = re.subn(
    r'module "(route_[^"]+)" \{\n  source = "../../../modules/core/cross-cluster-http"\n',
    r'module "\1" {\n  source = "../../../modules/core/cross-cluster-http"\n  count  = local.cross_cluster_routes ? 1 : 0\n',
    text,
)
print("route counts added", n)

text = text.replace(", data.external.platform_node_ip]", "]")

text = text.replace(
    'output "cluster_name" { value = module.cluster.cluster_name }\noutput "api_server_port" { value = module.cluster.api_server_port }',
    'output "cluster_name" { value = local.kind_name }\noutput "api_server_port" { value = local.co_locate_on_infra ? 6443 : try(module.cluster[0].api_server_port, 6445) }\noutput "co_locate_on_infra" { value = local.co_locate_on_infra }',
)

for i, line in enumerate(text.splitlines(), 1):
    if "gateway_same_cluster" in line and "false" in line:
        print("WARN", i, line)
    if "module.cluster." in line and "module.cluster[0]" not in line and "count" not in line:
        # may still be ok in comments
        if "module.cluster.cluster" in line or "module.cluster.endpoint" in line or "module.cluster.api" in line:
            print("REF", i, line)

p.write_text(text, encoding="utf-8", newline="\n")
print("OK", p)
