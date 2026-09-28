from pathlib import Path
import re

p = Path(r"f:\am-repos\am-repos\am-infra-automation\terraform\kind-fleet\dev\platform\main.tf")
text = p.read_text(encoding="utf-8").replace("\r\n", "\n")

old_header = """# Phase 3a–3d platform: Keycloak + Argo + Temporal + Lago + P1 UIs (n8n…novu).
# Traefik stays on infra; cross-cluster-http bridges published hosts.
"""
new_header = """# Phase 3a–3d platform: Keycloak + Argo + Temporal + Lago + P1 UIs (n8n…novu).
# identity-infra-split: set co_locate_on_infra=true → am-dev-infra (no platform Kind).
# Default false keeps am-dev-platform :6445.
"""
if old_header not in text:
    raise SystemExit("header mismatch")
text = text.replace(old_header, new_header, 1)

old_cluster = """module \"cluster\" {
  source          = \"../../../modules/core/cluster\"
  env             = local.env
  cluster_role    = \"platform\"
  api_server_port = 6445
  node_shape      = \"one\"
}

resource \"local_file\" \"kubeconfig\" {
  content         = module.cluster.kubeconfig
  filename        = pathexpand(\"~/.asrax/kubeconfig.am-dev-platform.yaml\")
  file_permission = \"0600\"
}

data \"external\" \"platform_node_ip\" {
  program    = [\"PowerShell\", \"-NoProfile\", \"-File\", \"${path.module}/scripts/platform-ip.ps1\"]
  depends_on = [module.cluster, local_file.kubeconfig]
}

module \"namespaces\" {
  source            = \"../../../modules/core/namespaces\"
  environment       = local.env
  create_identity   = true
  create_apps       = false
  create_github     = false
  create_monitoring = false
  extra_namespaces  = [\"argocd\", \"temporal\", \"billing\", \"n8n\", \"growthbook\", \"openproject\", \"am-ai\", \"notification\"]

  depends_on = [module.cluster, local_file.kubeconfig]
}

# Pull Phase 3d images into KinD node containerd (crictl) before Helm/Deploy.
# Do not use host `docker pull` alone — pods run on the kind node, not local Docker.
module \"image_preload_3d\" {
  source       = \"../../../modules/core/kind-image-preload\"
  cluster_name = module.cluster.cluster_name
"""

new_cluster = """module \"cluster\" {
  count           = local.co_locate_on_infra ? 0 : 1
  source          = \"../../../modules/core/cluster\"
  env             = local.env
  cluster_role    = \"platform\"
  api_server_port = 6445
  node_shape      = \"one\"
}

resource \"local_file\" \"kubeconfig\" {
  count           = local.co_locate_on_infra ? 0 : 1
  content         = module.cluster[0].kubeconfig
  filename        = pathexpand(\"~/.asrax/kubeconfig.am-dev-platform.yaml\")
  file_permission = \"0600\"
}

data \"external\" \"platform_node_ip\" {
  count      = local.co_locate_on_infra ? 0 : 1
  program    = [\"PowerShell\", \"-NoProfile\", \"-File\", \"${path.module}/scripts/platform-ip.ps1\"]
  depends_on = [module.cluster, local_file.kubeconfig]
}

resource \"terraform_data\" \"kind_ready\" {
  input = local.co_locate_on_infra ? \"am-dev-infra\" : module.cluster[0].cluster_name
}

locals {
  platform_ip = local.co_locate_on_infra ? \"\" : coalesce(var.platform_node_ip, try(data.external.platform_node_ip[0].result.ip, \"\"))
  kind_name   = local.co_locate_on_infra ? \"am-dev-infra\" : module.cluster[0].cluster_name
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

# Pull Phase 3d images into KinD node containerd (crictl) before Helm/Deploy.
# Do not use host `docker pull` alone — pods run on the kind node, not local Docker.
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

# Fix any remaining locals that referenced platform_ip before we added locals block
# There may already be a locals { platform_ip = ... } later — merge/remove duplicate
# Find old platform_ip local if present
text2 = re.sub(
    r"\nlocals \{\n  platform_ip = coalesce\(var\.platform_node_ip, try\(data\.external\.platform_node_ip\.result\.ip, \"\"\)\)\n",
    "\nlocals {\n  # platform_ip / kind_name set above with co_locate\n  _unused_legacy_platform_ip = \"\"\n",
    text,
    count=1,
)
if text2 != text:
    text = text2
    print("replaced duplicate platform_ip locals")

text = re.sub(
    r"gateway_same_cluster(\s*)=\s*false",
    r"gateway_same_cluster\1= local.gateway_same_cluster",
    text,
)

text = text.replace(
    '      KUBECONFIG = pathexpand("~/.asrax/kubeconfig.am-dev-platform.yaml")',
    "      KUBECONFIG = local.workload_kubeconfig",
)

text, n = re.subn(
    r'module "(route_[^"]+)" \{\n  source = "../../../modules/core/cross-cluster-http"\n',
    r'module "\1" {\n  source = "../../../modules/core/cross-cluster-http"\n  count  = local.cross_cluster_routes ? 1 : 0\n',
    text,
)
print("route counts", n)

# backend_ip references
text = text.replace(
    "backend_ip   = coalesce(var.platform_node_ip, try(data.external.platform_node_ip.result.ip, \"\"))",
    "backend_ip   = local.platform_ip",
)
text = text.replace(
    "backend_ip   = data.external.platform_node_ip.result.ip",
    "backend_ip   = local.platform_ip",
)

text = text.replace(
    'output "cluster_name" { value = module.cluster.cluster_name }\noutput "api_server_port" { value = module.cluster.api_server_port }',
    'output "cluster_name" { value = local.kind_name }\noutput "api_server_port" { value = local.co_locate_on_infra ? 6443 : try(module.cluster[0].api_server_port, 6445) }\noutput "co_locate_on_infra" { value = local.co_locate_on_infra }',
)

# depends_on data.external.platform_node_ip
text = text.replace(", data.external.platform_node_ip]", "]")
text = text.replace("[module.keycloak, data.external.platform_node_ip]", "[module.keycloak]")

for i, line in enumerate(text.splitlines(), 1):
    if "module.cluster." in line and "module.cluster[0]" not in line and "count" not in line:
        if any(x in line for x in ("cluster_name", "endpoint", "kubeconfig", "api_server")):
            print("REF", i, line.strip())

p.write_text(text, encoding="utf-8", newline="\n")
print("OK", p)
