#!/usr/bin/env python3
"""Batch Contabo preprod Argo sync (sync-order waves, batchSize=2). Auto-sync off first."""
from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

PROD_KC = Path.home() / ".asrax" / "kubeconfig.prod"
GITOPS = Path(__file__).resolve().parents[2] / "am-gitops"
SYNC_ORDER = GITOPS / "catalog" / "sync-order.yaml"

# Services enrolled in Contabo preprod fleets (exclude n8n/engage/resume/ui-test if absent)
PREPROD_SUFFIX = "-preprod"


def kubectl(*args: str, input_text: str | None = None) -> subprocess.CompletedProcess:
    cmd = [
        "kubectl",
        "--kubeconfig",
        str(PROD_KC),
        "--context",
        "prod-infra",
        "-n",
        "argocd",
        *args,
    ]
    return subprocess.run(cmd, input=input_text, capture_output=True, text=True)


def load_waves(batch_size_override: int | None = None):
    import yaml

    data = yaml.safe_load(SYNC_ORDER.read_text(encoding="utf-8"))
    batch_size = int(batch_size_override or data.get("batchSize") or 2)
    pause = int(data.get("pauseSeconds") or 45)
    timeout = int(data.get("waitHealthyTimeoutSeconds") or 180)
    waves_map = data.get("waves") or {}
    # sort wave keys numerically (allow -1)
    keys = sorted(waves_map.keys(), key=lambda k: int(str(k)))
    ordered: list[str] = []
    for k in keys:
        for svc in waves_map[k]:
            # skip services not in lean Contabo preprod
            if svc in ("n8n", "am-engage", "am-resume", "am-ui-test-agent"):
                continue
            ordered.append(svc)
    batches: list[list[str]] = []
    for i in range(0, len(ordered), batch_size):
        batches.append(ordered[i : i + batch_size])
    return batches, pause, timeout


def list_preprod_apps() -> dict[str, dict]:
    r = kubectl("get", "applications", "-o", "json")
    r.check_returncode()
    out = {}
    for it in json.loads(r.stdout).get("items") or []:
        name = it["metadata"]["name"]
        if not name.endswith(PREPROD_SUFFIX):
            continue
        out[name] = it
    return out


def disable_auto(apps: dict[str, dict]) -> int:
    n = 0
    for name, it in apps.items():
        sp = (it.get("spec") or {}).get("syncPolicy") or {}
        if "automated" not in sp:
            continue
        # JSON patch remove automated
        patch = [{"op": "remove", "path": "/spec/syncPolicy/automated"}]
        r = kubectl("patch", "application", name, "--type=json", "-p", json.dumps(patch))
        print(f"  auto-off {name}: rc={r.returncode} {(r.stderr or r.stdout)[:120]}")
        n += 1
    return n


def app_status(name: str) -> tuple[str, str]:
    r = kubectl("get", "application", name, "-o", "json")
    if r.returncode != 0:
        return "Missing", "Missing"
    it = json.loads(r.stdout)
    st = it.get("status") or {}
    return (
        (st.get("sync") or {}).get("status") or "Unknown",
        (st.get("health") or {}).get("status") or "Unknown",
    )


def sync_app(name: str) -> None:
    # Contabo Argo sync via kubectl merge patch (works without argocd CLI)
    body = {
        "metadata": {
            "annotations": {
                "argocd.argoproj.io/refresh": "hard",
            }
        },
        "operation": {
            "initiatedBy": {"username": "am-batch-deploy"},
            "sync": {
                "syncOptions": ["RespectIgnoreDifferences=true", "CreateNamespace=false"],
            },
        },
    }
    r = kubectl("patch", "application", name, "--type=merge", "-p", json.dumps(body))
    print(f"  sync {name}: rc={r.returncode} {(r.stderr or r.stdout)[:160]}")


def scale_services(svcs: list[str], replicas: int = 1) -> None:
    """AppSets ignore /spec/replicas — must scale on cluster after sync."""
    script = ["set +e", "CP=am-preprod-control-plane", 'k(){ docker exec "$CP" kubectl "$@"; }']
    for svc in svcs:
        for ns in ("am-apps-preprod", "am-agents-preprod"):
            for name in (f"{svc}-preprod", svc):
                script.append(
                    f'k -n {ns} scale deploy/{name} --replicas={replicas} 2>/dev/null '
                    f'&& echo scaled {ns}/{name}={replicas}'
                )
    remote = "\n".join(script)
    r = subprocess.run(
        [
            "ssh.exe",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=20",
            "-o",
            "IdentitiesOnly=yes",
            "-p",
            "7576",
            "-i",
            str(Path.home() / ".ssh" / "id_ed25519_hts_vps"),
            "root@103.127.146.57",
            remote,
        ],
        capture_output=True,
        text=True,
    )
    print((r.stdout or "")[:800])
    if r.returncode != 0:
        print((r.stderr or "")[:300])


def wait_batch(names: list[str], timeout: int) -> bool:
    """Advance when Synced; Healthy preferred, Progressing OK. Don't stall forever on Degraded."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        rows = []
        all_synced = True
        any_progress = False
        for name in names:
            sync, health = app_status(name)
            rows.append(f"{name}: sync={sync} health={health}")
            if sync != "Synced":
                all_synced = False
            if health in ("Healthy", "Progressing"):
                any_progress = True
        print("    " + " | ".join(rows))
        if all_synced and (any_progress or all(app_status(n)[1] in ("Healthy", "Progressing", "Degraded") for n in names)):
            # Give Healthy a bit more time if Progressing
            if all(app_status(n)[1] == "Healthy" for n in names):
                return True
            if time.time() + 30 >= deadline and all_synced:
                return True
        time.sleep(15)
    print("    timeout — continuing to next batch")
    return False


def main() -> int:
    only_wave = None
    batch_size_override = None
    start_from = 0
    for arg in sys.argv[1:]:
        if arg.startswith("--batch="):
            only_wave = int(arg.split("=", 1)[1])
        elif arg.startswith("--batch-size="):
            batch_size_override = int(arg.split("=", 1)[1])
        elif arg.startswith("--start="):
            start_from = int(arg.split("=", 1)[1])

    batches, pause, timeout = load_waves(batch_size_override)
    print(f"batches={len(batches)} size~{len(batches[0]) if batches else 0} pause={pause}s timeout={timeout}s")

    apps = list_preprod_apps()
    print(f"preprod apps on Contabo: {len(apps)}")
    print(f"disable auto-sync: {disable_auto(apps)}")

    # map service -> app name
    def app_name(svc: str) -> str:
        return f"{svc}{PREPROD_SUFFIX}"

    if only_wave is not None:
        start = only_wave
        end = only_wave + 1
    else:
        start = start_from
        end = len(batches)

    for i in range(start, end):
        svcs = batches[i]
        names = [app_name(s) for s in svcs if app_name(s) in apps]
        missing = [s for s in svcs if app_name(s) not in apps]
        print(f"\n=== batch {i+1}/{len(batches)}: {svcs} ===")
        if missing:
            print(f"  skip missing apps: {missing}")
        if not names:
            continue
        for n in names:
            sync_app(n)
        scale_services(svcs, replicas=1)
        print(f"  wait up to {timeout}s...")
        wait_batch(names, timeout)
        if i + 1 < end:
            print(f"  pause {pause}s before next batch")
            time.sleep(pause)

    print("\n=== final status ===")
    for name in sorted(apps):
        print(f"  {name}: sync={app_status(name)[0]} health={app_status(name)[1]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
