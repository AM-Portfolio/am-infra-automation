#!/usr/bin/env python3
"""Apply + sync all prod Application CRs from /tmp/gitops-prod (closout remaining)."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import yaml

ROOT = Path("/tmp/gitops-prod/prod")
# Priority order then everything else under apps/ + agents/
PRIORITY = [
    "agents/am-qa-agents.yaml",
    "agents/am-support-agent.yaml",
    "agents/am-tool-agent.yaml",
    "agents/am-mcp-server.yaml",
    "agents/am-db-agent.yaml",
    "agents/am-fin-agent.yaml",
    "apps/am-gateway.yaml",
    "apps/am-api-gateway.yaml",
    "apps/am-analysis.yaml",
    "apps/am-document-processor.yaml",
    "apps/am-notification.yaml",
    "apps/am-subscription.yaml",
    "apps/am-asrax-corp.yaml",
    "apps/am-asrax-ui.yaml",
    "apps/am-asrax-proxy.yaml",
    "agents/am-mkt-agents.yaml",
    "agents/am-mkt-portal-ui.yaml",
]


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, text=True, **kw)


def app_name_from_yaml(path: Path) -> str:
    doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    return doc["metadata"]["name"]


def apply_app(path: Path) -> str:
    os.environ["KUBECONFIG"] = "/data/am-state/kubeconfig.am-prod-platform.yaml"
    desired = yaml.safe_load(path.read_text(encoding="utf-8"))
    name = desired["metadata"]["name"]
    app = json.loads(
        subprocess.check_output(["kubectl", "-n", "argocd", "get", "app", name, "-o", "json"])
    )
    for k in ("sources", "project", "destination", "syncPolicy", "ignoreDifferences"):
        if k in desired.get("spec", {}):
            app["spec"][k] = desired["spec"][k]
    # Prefer branch with Kind-fleet pins until merged to main.
    gitops_rev = os.environ.get("GITOPS_REV", "").strip()
    if gitops_rev:
        for src in app["spec"].get("sources") or []:
            if src.get("ref") == "imageValues" or (
                "am-gitops" in (src.get("repoURL") or "") and src.get("ref") == "imageValues"
            ):
                src["targetRevision"] = gitops_rev
            if src.get("ref") == "imageValues" or (
                isinstance(src.get("repoURL"), str)
                and "am-gitops" in src.get("repoURL", "")
                and not src.get("path")
            ):
                src["targetRevision"] = gitops_rev
    helm = app["spec"]["sources"][0].get("helm") or {}
    if "values" in helm and isinstance(helm["values"], str):
        helm["values"] = helm["values"].replace("\u2014", "-").replace("\u2013", "-")
        yaml.safe_load(helm["values"])
        app["spec"]["sources"][0]["helm"] = helm
    out = Path(f"/tmp/{name}-merged.json")
    out.write_text(json.dumps(app), encoding="utf-8")
    run(["kubectl", "-n", "argocd", "replace", "-f", str(out)])
    print(f"applied {name}", flush=True)
    return name


def sync_app(name: str) -> None:
    os.environ["KUBECONFIG"] = "/data/am-state/kubeconfig.am-prod-platform.yaml"
    patch = {
        "operation": {
            "initiatedBy": {"username": "admin"},
            "info": [{"name": "reason", "value": "closout-remaining"}],
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
    print(f"synced {name}", flush=True)


def collect() -> list[Path]:
    seen = set()
    paths: list[Path] = []
    for rel in PRIORITY:
        p = ROOT / rel
        if p.exists():
            paths.append(p)
            seen.add(rel.replace("\\", "/"))
    for sub in ("apps", "agents"):
        d = ROOT / sub
        if not d.is_dir():
            continue
        for p in sorted(d.glob("*.yaml")):
            rel = f"{sub}/{p.name}"
            if rel not in seen:
                paths.append(p)
    return paths


def main() -> int:
    start = None
    args = sys.argv[1:]
    if "--start-from" in args:
        i = args.index("--start-from")
        start = args[i + 1]
    paths = collect()
    started = start is None
    for p in paths:
        name = app_name_from_yaml(p)
        if not started:
            if name == start or p.name == start or name.endswith(start or ""):
                started = True
            else:
                print(f"skip {name}", flush=True)
                continue
        try:
            apply_app(p)
            sync_app(name)
            time.sleep(2)
        except Exception as e:
            print(f"FAIL {name}: {e}", flush=True)
    print("CLOSOUT_SYNC_DONE", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
