#!/usr/bin/env python3
"""Phase 4f: apply hostAliases-cleared Application CRs + Argo sync (portfolio→trade→doc→news→analysis)."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import yaml

APPS = [
    ("am-portfolio-prod", "am-portfolio.yaml"),
    ("am-trade-management-service-prod", "am-trade-management-service.yaml"),
    ("am-document-processor-prod", "am-document-processor.yaml"),
    ("am-news-prod", "am-news.yaml"),
    ("am-analysis-prod", "am-analysis.yaml"),
]


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, text=True, **kw)


def apply_app(name: str, yaml_path: Path) -> None:
    os.environ["KUBECONFIG"] = "/data/am-state/kubeconfig.am-prod-platform.yaml"
    desired = yaml.safe_load(yaml_path.read_text(encoding="utf-8"))
    app = json.loads(
        subprocess.check_output(
            ["kubectl", "-n", "argocd", "get", "app", name, "-o", "json"]
        )
    )
    for k in ("sources", "project", "destination", "syncPolicy", "ignoreDifferences"):
        if k in desired.get("spec", {}):
            app["spec"][k] = desired["spec"][k]
    # scrub smart dashes in values
    helm = app["spec"]["sources"][0].get("helm") or {}
    if "values" in helm and isinstance(helm["values"], str):
        helm["values"] = (
            helm["values"].replace("\u2014", "-").replace("\u2013", "-")
        )
        yaml.safe_load(helm["values"])
        app["spec"]["sources"][0]["helm"] = helm
    out = Path(f"/tmp/{name}-merged.json")
    out.write_text(json.dumps(app), encoding="utf-8")
    run(["kubectl", "-n", "argocd", "replace", "-f", str(out)])
    print(f"applied {name}")


def sync_app(name: str, timeout_s: int = 420) -> None:
    os.environ["KUBECONFIG"] = "/data/am-state/kubeconfig.am-prod-platform.yaml"
    patch = {
        "operation": {
            "initiatedBy": {"username": "admin"},
            "info": [{"name": "reason", "value": "phase-4f"}],
            "sync": {"prune": False, "syncStrategy": {"hook": {}}},
        }
    }
    run(
        [
            "kubectl",
            "-n",
            "argocd",
            "patch",
            "application",
            name,
            "--type",
            "merge",
            "--patch",
            json.dumps(patch),
        ]
    )
    deadline = time.time() + timeout_s
    i = 0
    while time.time() < deadline:
        i += 1
        st = json.loads(
            subprocess.check_output(
                ["kubectl", "-n", "argocd", "get", "app", name, "-o", "json"]
            )
        )
        sync = (st.get("status") or {}).get("sync", {}).get("status")
        health = (st.get("status") or {}).get("health", {}).get("status")
        op = (st.get("status") or {}).get("operationState") or {}
        phase = op.get("phase")
        print(f"{name} i={i} sync={sync} health={health} phase={phase}")
        if phase in ("Failed", "Error"):
            print("MSG", op.get("message"))
            raise SystemExit(f"sync failed: {name}")
        if sync == "Synced" and health in ("Healthy", "Progressing", "Suspended"):
            # prefer Healthy; Progressing OK while pods start — wait a bit more if Progressing
            if health == "Healthy" and phase in ("Succeeded", None, ""):
                break
            if health == "Healthy" and phase == "Succeeded":
                break
            if sync == "Synced" and phase == "Succeeded" and health != "Degraded":
                # wait for Ready separately via apps kubeconfig
                break
        time.sleep(5)
    else:
        raise SystemExit(f"timeout syncing {name}")

    # wait deploy Ready on apps cluster
    os.environ["KUBECONFIG"] = "/data/am-state/kubeconfig.am-prod-apps.yaml"
    # release name ≈ app name
    deploy = name  # Application releaseName matches
    for j in range(1, 49):
        try:
            ready = subprocess.check_output(
                [
                    "kubectl",
                    "-n",
                    "am-apps-prod",
                    "get",
                    "deploy",
                    deploy,
                    "-o",
                    "jsonpath={.status.readyReplicas}",
                ],
                text=True,
            ).strip()
        except subprocess.CalledProcessError:
            ready = "0"
        print(f"{deploy} readyReplicas={ready or 0} j={j}")
        if ready and int(ready) >= 1:
            # reject laptop hostAliases
            dep = subprocess.check_output(
                ["kubectl", "-n", "am-apps-prod", "get", "deploy", deploy, "-o", "yaml"],
                text=True,
            )
            if "192.168.1.11" in dep:
                raise SystemExit(f"{deploy} still has laptop hostAliases")
            print(f"READY {deploy}")
            return
        time.sleep(5)
    raise SystemExit(f"deploy not ready: {deploy}")


def main() -> int:
    apps_dir = Path("/tmp/gitops-prod-apps")
    start = None
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] in ("--start-from", "-f") and i + 1 < len(args):
            start = args[i + 1]
            i += 2
            continue
        if not args[i].startswith("-"):
            apps_dir = Path(args[i])
        i += 1
    started = start is None
    for name, fname in APPS:
        if not started:
            if name == start or fname == start or name.endswith(start):
                started = True
            else:
                print(f"skip {name}")
                continue
        apply_app(name, apps_dir / fname)
        sync_app(name)
    print("WAVE_4F_SYNC_DONE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
