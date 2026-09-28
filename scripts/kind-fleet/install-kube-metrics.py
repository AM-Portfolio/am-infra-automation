#!/usr/bin/env python3
"""Install kube-state-metrics + node-exporter into monitoring (fleet Alloy scrape targets).

Usage:
  python scripts/kind-fleet/install-kube-metrics.py --kubeconfig ~/.asrax/kubeconfig.vps --context am-vps-nonprod
  python scripts/kind-fleet/install-kube-metrics.py --kubeconfig ... --context am-prod-apps
"""
from __future__ import annotations

import argparse
import subprocess
import sys

NS = "monitoring"
KSM_RELEASE = "kube-state-metrics"
NE_RELEASE = "node-exporter"
REPO = "prometheus-community"
REPO_URL = "https://prometheus-community.github.io/helm-charts"


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(cmd), flush=True)
    return subprocess.run(cmd, check=check, text=True, capture_output=False)


def helm_base(kubeconfig: str | None, context: str | None) -> list[str]:
    cmd = ["helm"]
    if kubeconfig:
        cmd += ["--kubeconfig", kubeconfig]
    if context:
        cmd += ["--kube-context", context]
    return cmd


def kubectl_base(kubeconfig: str | None, context: str | None) -> list[str]:
    cmd = ["kubectl"]
    if kubeconfig:
        cmd += ["--kubeconfig", kubeconfig]
    if context:
        cmd += ["--context", context]
    return cmd


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--kubeconfig", default=None)
    p.add_argument("--context", default=None)
    p.add_argument("--namespace", default=NS)
    args = p.parse_args()

    kb = kubectl_base(args.kubeconfig, args.context)
    hb = helm_base(args.kubeconfig, args.context)

    run(kb + ["create", "namespace", args.namespace], check=False)
    run(hb + ["repo", "add", REPO, REPO_URL], check=False)
    run(hb + ["repo", "update", REPO], check=False)

    run(
        hb
        + [
            "upgrade",
            "--install",
            KSM_RELEASE,
            f"{REPO}/kube-state-metrics",
            "--namespace",
            args.namespace,
            "--set",
            "metricLabelsAllowlist[0]=pods=[*]",
            "--set",
            "metricAnnotationsAllowList[0]=pods=[*]",
            "--wait",
            "--timeout",
            "3m",
        ]
    )

    # hostNetwork/hostPID so Kind nodes expose real rootfs stats; Alloy scrapes the Service.
    run(
        hb
        + [
            "upgrade",
            "--install",
            NE_RELEASE,
            f"{REPO}/prometheus-node-exporter",
            "--namespace",
            args.namespace,
            "--set",
            "hostNetwork=true",
            "--set",
            "hostPID=true",
            "--set",
            "containerSecurityContext.privileged=true",
            "--wait",
            "--timeout",
            "3m",
        ]
    )

    run(kb + ["-n", args.namespace, "get", "deploy,ds,svc", "-l", f"app.kubernetes.io/name"])
    print("OK: kube-state-metrics + node-exporter ready in", args.namespace)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as exc:
        print(f"FAILED: {exc}", file=sys.stderr)
        raise SystemExit(exc.returncode or 1)
