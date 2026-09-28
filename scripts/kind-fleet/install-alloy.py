#!/usr/bin/env python3
"""Install Alloy DaemonSet via Helm on a fleet cluster (Phase 6+ VPS labels)."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

CHART_VERSION = "0.9.2"
LOKI = "https://loki.asrax.in/loki/api/v1/push"
PROM = "https://prometheus.asrax.in/api/v1/write"

# Stable inventory (matches am-obs-platform compiler/catalog/fleet-inventory.yaml)
VPS_BY_ENV = {
    "prod": ("vps-prod", "VPS_PROD", "203.174.22.129"),
    "dr": ("vps-dr", "VPS_DR", "129.121.128.131"),
    "preprod": ("vps-preprod", "VPS_PREPROD", "103.127.146.57"),
    "dev": ("vps-dev", "VPS_DEV", "laptop"),
    "obs": ("vps-obs", "VPS_OBS", "129.121.132.116"),
}


def river(
    cluster: str,
    environment: str,
    vps: str,
    vps_name: str,
    vps_ip: str,
) -> str:
    return f"""
logging {{
  level  = "info"
  format = "logfmt"
}}

discovery.kubernetes "pods" {{
  role = "pod"
}}

discovery.relabel "pods" {{
  targets = discovery.kubernetes.pods.targets

  rule {{
    source_labels = ["__meta_kubernetes_namespace"]
    target_label  = "namespace"
  }}
  rule {{
    source_labels = ["__meta_kubernetes_pod_name"]
    target_label  = "pod"
  }}
  rule {{
    source_labels = ["__meta_kubernetes_pod_container_name"]
    target_label  = "container"
  }}
  rule {{
    source_labels = ["__meta_kubernetes_pod_node_name"]
    target_label  = "node"
  }}
  rule {{
    target_label = "vps"
    replacement  = "{vps}"
  }}
  rule {{
    target_label = "vps_name"
    replacement  = "{vps_name}"
  }}
  rule {{
    target_label = "vps_ip"
    replacement  = "{vps_ip}"
  }}
  rule {{
    target_label = "cluster"
    replacement  = "{cluster}"
  }}
  rule {{
    target_label = "environment"
    replacement  = "{environment}"
  }}
  rule {{
    source_labels = ["__meta_kubernetes_pod_container_name"]
    regex         = "^(.+)-dev$"
    replacement   = "$1"
    target_label  = "application"
  }}
  rule {{
    source_labels = ["application", "__meta_kubernetes_pod_container_name"]
    separator     = ";"
    regex         = "^;(.+)$"
    replacement   = "$1"
    target_label  = "application"
  }}
  rule {{
    source_labels = ["__meta_kubernetes_namespace", "__meta_kubernetes_pod_name", "__meta_kubernetes_pod_container_name"]
    separator     = "/"
    target_label  = "job"
  }}
  rule {{
    source_labels = ["__meta_kubernetes_pod_uid", "__meta_kubernetes_pod_container_name"]
    separator     = "/"
    target_label  = "__path__"
    replacement   = "/var/log/pods/*$1/*.log"
  }}
}}

loki.source.kubernetes "pods" {{
  targets    = discovery.relabel.pods.output
  forward_to = [loki.write.default.receiver]
}}

loki.write "default" {{
  endpoint {{
    url = "{LOKI}"
  }}
  external_labels = {{
    vps         = "{vps}",
    vps_name    = "{vps_name}",
    vps_ip      = "{vps_ip}",
    cluster     = "{cluster}",
    environment = "{environment}",
  }}
}}

discovery.kubernetes "metrics_pods" {{
  role = "pod"
}}

discovery.relabel "metrics_pods" {{
  targets = discovery.kubernetes.metrics_pods.targets

  rule {{
    source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scrape"]
    action        = "keep"
    regex         = "true"
  }}
  rule {{
    source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scheme"]
    action        = "replace"
    target_label  = "__scheme__"
    regex         = "(https?)"
  }}
  rule {{
    source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_path"]
    action        = "replace"
    target_label  = "__metrics_path__"
    regex         = "(.+)"
  }}
  rule {{
    source_labels = ["__address__", "__meta_kubernetes_pod_annotation_prometheus_io_port"]
    action        = "replace"
    regex         = "(.+?)(?::[0-9]+)?;([0-9]+)"
    replacement   = "$1:$2"
    target_label  = "__address__"
  }}
  rule {{
    source_labels = ["__meta_kubernetes_namespace"]
    target_label  = "namespace"
  }}
  rule {{
    source_labels = ["__meta_kubernetes_pod_name"]
    target_label  = "pod"
  }}
  rule {{
    source_labels = ["__meta_kubernetes_pod_container_name"]
    target_label  = "container"
  }}
}}

prometheus.scrape "annotated_pods" {{
  targets         = discovery.relabel.metrics_pods.output
  forward_to      = [prometheus.remote_write.fleet.receiver]
  scrape_interval = "30s"
  // Keep exporter metric labels (e.g. am_release_* namespace=am-apps-*) over k8s target labels.
  honor_labels    = true
}}

discovery.kubernetes "ksm_services" {{
  role = "service"
}}

discovery.relabel "kube_state_metrics" {{
  targets = discovery.kubernetes.ksm_services.targets

  rule {{
    source_labels = ["__meta_kubernetes_service_label_app_kubernetes_io_name", "__meta_kubernetes_service_name"]
    separator     = ";"
    regex         = ".*kube-state-metrics.*"
    action        = "keep"
  }}
  rule {{
    source_labels = ["__meta_kubernetes_service_port_number"]
    regex         = "^(8080|8081)$"
    action        = "keep"
  }}
  // Keep kube_* metric namespace labels (do not overwrite with KSM Service ns).
}}

prometheus.scrape "kube_state_metrics" {{
  targets         = discovery.relabel.kube_state_metrics.output
  forward_to      = [prometheus.remote_write.fleet.receiver]
  scrape_interval = "30s"
}}

discovery.kubernetes "node_exporter_services" {{
  role = "service"
}}

discovery.relabel "node_exporter" {{
  targets = discovery.kubernetes.node_exporter_services.targets

  rule {{
    source_labels = ["__meta_kubernetes_service_label_app_kubernetes_io_name", "__meta_kubernetes_service_name"]
    separator     = ";"
    regex         = ".*node-exporter.*"
    action        = "keep"
  }}
  rule {{
    source_labels = ["__meta_kubernetes_service_port_number"]
    regex         = "^(9100)$"
    action        = "keep"
  }}
  rule {{
    source_labels = ["__meta_kubernetes_pod_node_name", "__meta_kubernetes_endpoint_node_name"]
    separator     = ";"
    regex         = "^([^;]+);.*$|;(.+)$"
    replacement   = "$1$2"
    target_label  = "instance"
  }}
  rule {{
    source_labels = ["__meta_kubernetes_namespace"]
    target_label  = "namespace"
  }}
}}

prometheus.scrape "node_exporter" {{
  targets         = discovery.relabel.node_exporter.output
  forward_to      = [prometheus.remote_write.fleet.receiver]
  scrape_interval = "30s"
}}

discovery.kubernetes "nodes" {{
  role = "node"
}}

discovery.relabel "cadvisor" {{
  targets = discovery.kubernetes.nodes.targets

  rule {{
    target_label = "__address__"
    replacement  = "kubernetes.default.svc.cluster.local:443"
  }}
  rule {{
    source_labels = ["__meta_kubernetes_node_name"]
    regex         = "(.+)"
    replacement   = "/api/v1/nodes/$1/proxy/metrics/cadvisor"
    target_label  = "__metrics_path__"
  }}
  rule {{
    source_labels = ["__meta_kubernetes_node_name"]
    target_label  = "node"
  }}
  rule {{
    source_labels = ["__meta_kubernetes_node_name"]
    target_label  = "instance"
  }}
}}

prometheus.scrape "cadvisor" {{
  targets           = discovery.relabel.cadvisor.output
  forward_to        = [prometheus.remote_write.fleet.receiver]
  scrape_interval   = "30s"
  scheme            = "https"
  bearer_token_file = "/var/run/secrets/kubernetes.io/serviceaccount/token"
  tls_config {{
    insecure_skip_verify = true
    ca_file              = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
  }}
}}

prometheus.remote_write "fleet" {{
  endpoint {{
    url = "{PROM}"
  }}
  external_labels = {{
    vps         = "{vps}",
    vps_name    = "{vps_name}",
    vps_ip      = "{vps_ip}",
    cluster     = "{cluster}",
    environment = "{environment}",
  }}
}}
""".strip() + "\n"


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--kubeconfig", required=True)
    p.add_argument("--context", default="")
    p.add_argument("--cluster-name", required=True)
    p.add_argument("--environment", required=True)
    p.add_argument("--vps", default="")
    p.add_argument("--vps-name", default="")
    p.add_argument("--vps-ip", default="")
    args = p.parse_args()

    vps, vps_name, vps_ip = VPS_BY_ENV.get(args.environment, ("", "", ""))
    if args.vps:
        vps = args.vps
    if args.vps_name:
        vps_name = args.vps_name
    if args.vps_ip:
        vps_ip = args.vps_ip
    if not vps or not vps_name or not vps_ip:
        print(
            f"ERROR: unknown environment={args.environment!r}; pass --vps/--vps-name/--vps-ip",
            file=sys.stderr,
        )
        return 2

    kc = str(Path(args.kubeconfig).expanduser())

    def kubectl(*a: str) -> None:
        cmd = ["kubectl", "--kubeconfig", kc]
        if args.context:
            cmd += ["--context", args.context]
        subprocess.check_call([*cmd, *a])

    def helm(*a: str) -> None:
        cmd = ["helm", "--kubeconfig", kc]
        if args.context:
            cmd += ["--kube-context", args.context]
        subprocess.check_call([*cmd, *a])

    ns_cmd = ["kubectl", "--kubeconfig", kc]
    if args.context:
        ns_cmd += ["--context", args.context]
    ns_yaml = subprocess.check_output(
        [*ns_cmd, "create", "namespace", "monitoring", "--dry-run=client", "-o", "yaml"],
        text=True,
    )
    subprocess.run(
        [*ns_cmd, "apply", "-f", "-"],
        input=ns_yaml,
        text=True,
        check=True,
    )

    values = {
        "alloy": {
            "configMap": {
                "content": river(
                    args.cluster_name, args.environment, vps, vps_name, vps_ip
                )
            },
            "mounts": {"varlog": True},
        },
        "controller": {"type": "daemonset"},
        "serviceAccount": {"create": True},
        "rbac": {"create": True},
        "crds": {"create": False},
    }
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(values, f)
        values_path = f.name
    try:
        helm(
            "upgrade",
            "--install",
            "alloy",
            "grafana/alloy",
            "--version",
            CHART_VERSION,
            "--namespace",
            "monitoring",
            "--values",
            values_path,
            "--wait",
            "--timeout",
            "10m",
        )
    finally:
        os.unlink(values_path)

    kubectl("rollout", "status", "daemonset/alloy", "-n", "monitoring", "--timeout=180s")
    print(
        f"OK alloy on {args.cluster_name} env={args.environment} "
        f"vps={vps} ({vps_name}/{vps_ip})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
