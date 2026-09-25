#!/usr/bin/env python3
"""Phase 4g: apply Application CRs + Argo sync remaining apps + agents."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import yaml

# Order: store consumers first, then secondary, then agents.
APPS = [
    ("am-parser-prod", "apps/am-parser.yaml", "am-apps-prod"),
    ("am-notification-prod", "apps/am-notification.yaml", "am-apps-prod"),
    ("am-subscription-prod", "apps/am-subscription.yaml", "am-apps-prod"),
    ("am-oms-prod", "apps/am-oms.yaml", "am-apps-prod"),
    ("am-user-platform-prod", "apps/am-user-platform.yaml", "am-apps-prod"),
    ("am-logging-prod", "apps/am-logging.yaml", "am-apps-prod"),
    ("am-email-extractor-prod", "apps/am-email-extractor.yaml", "am-apps-prod"),
    ("am-cloudinary-manager-prod", "apps/am-cloudinary-manager.yaml", "am-apps-prod"),
    ("am-asrax-corp-prod", "apps/am-asrax-corp.yaml", "am-apps-prod"),
    ("am-asrax-ui-prod", "apps/am-asrax-ui.yaml", "am-apps-prod"),
    ("am-api-gateway-prod", "apps/am-api-gateway.yaml", "am-apps-prod"),
    ("am-mcp-server-prod", "agents/am-mcp-server.yaml", "am-agents-prod"),
    ("am-tool-agent-prod", "agents/am-tool-agent.yaml", "am-agents-prod"),
    ("am-support-agent-prod", "agents/am-support-agent.yaml", "am-agents-prod"),
    ("am-qa-agents-prod", "agents/am-qa-agents.yaml", "am-agents-prod"),
    ("am-fin-agent-prod", "agents/am-fin-agent.yaml", "am-agents-prod"),
    ("am-db-agent-prod", "agents/am-db-agent.yaml", "am-agents-prod"),
    ("am-mkt-agents-prod", "agents/am-mkt-agents.yaml", "am-agents-prod"),
    ("am-mkt-portal-ui-prod", "agents/am-mkt-portal-ui.yaml", "am-agents-prod"),
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
    print(f"applied {name}", flush=True)


def sync_app(name: str, ns: str, timeout_s: int = 480) -> None:
    os.environ["KUBECONFIG"] = "/data/am-state/kubeconfig.am-prod-platform.yaml"
    patch = {
        "operation": {
            "initiatedBy": {"username": "admin"},
            "info": [{"name": "reason", "value": "phase-4g"}],
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
        print(f"{name} i={i} sync={sync} health={health} phase={phase}", flush=True)
        if phase in ("Failed", "Error"):
            print("MSG", op.get("message"), flush=True)
            raise SystemExit(f"sync failed: {name}")
        if sync == "Synced" and phase in ("Succeeded", None, ""):
            break
        if sync == "Synced" and health in ("Healthy", "Progressing", "Suspended"):
            if phase == "Succeeded":
                break
        time.sleep(5)
    else:
        raise SystemExit(f"timeout syncing {name}")

    os.environ["KUBECONFIG"] = "/data/am-state/kubeconfig.am-prod-apps.yaml"
    # Release name may differ from Argo Application name (e.g. am-support-agent).
    for j in range(1, 61):
        try:
            out = subprocess.check_output(
                [
                    "kubectl",
                    "-n",
                    ns,
                    "get",
                    "deploy",
                    "-l",
                    f"app.kubernetes.io/instance={name}",
                    "-o",
                    "json",
                ],
                text=True,
            )
            items = json.loads(out).get("items") or []
        except subprocess.CalledProcessError:
            items = []
        ready_n = 0
        names = []
        for it in items:
            dname = it["metadata"]["name"]
            names.append(dname)
            rr = (it.get("status") or {}).get("readyReplicas") or 0
            if int(rr) >= 1:
                ready_n += 1
        print(
            f"{name} ns={ns} deploys={names or ['?']} readyCount={ready_n} j={j}",
            flush=True,
        )
        if items and ready_n >= 1 and ready_n == len(items):
            for it in items:
                dep_yaml = subprocess.check_output(
                    [
                        "kubectl",
                        "-n",
                        ns,
                        "get",
                        "deploy",
                        it["metadata"]["name"],
                        "-o",
                        "yaml",
                    ],
                    text=True,
                )
                if "192.168.1.11" in dep_yaml:
                    raise SystemExit(
                        f"{it['metadata']['name']} still has laptop hostAliases"
                    )
            print(f"READY {name}", flush=True)
            return
        # Fallback: exact deploy name match
        if not items:
            try:
                ready = subprocess.check_output(
                    [
                        "kubectl",
                        "-n",
                        ns,
                        "get",
                        "deploy",
                        name,
                        "-o",
                        "jsonpath={.status.readyReplicas}",
                    ],
                    text=True,
                ).strip()
            except subprocess.CalledProcessError:
                ready = "0"
            if ready and int(ready) >= 1:
                print(f"READY {name}", flush=True)
                return
        time.sleep(5)
    raise SystemExit(f"deploy not ready: {name}")


def main() -> int:
    root = Path("/tmp/gitops-prod")
    start = None
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] in ("--start-from", "-f") and i + 1 < len(args):
            start = args[i + 1]
            i += 2
            continue
        if not args[i].startswith("-"):
            root = Path(args[i])
        i += 1
    started = start is None
    for name, rel, ns in APPS:
        if not started:
            if name == start or rel.endswith(start) or name.endswith(start):
                started = True
            else:
                print(f"skip {name}", flush=True)
                continue
        apply_app(name, root / rel)
        sync_app(name, ns)
    print("WAVE_4G_SYNC_DONE", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
