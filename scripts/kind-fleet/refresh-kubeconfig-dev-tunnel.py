#!/usr/bin/env python3
"""Rebuild operator dig kubeconfigs for multi-laptop access via kubeapi-dev tunnel.

Writes two files under ~/.asrax (never commit either):

  kubeconfig.dev       → https://kubeapi-dev.asrax.in (bearer) — share with other laptops
  kubeconfig.dev.local → https://127.0.0.1:6444 (Kind client cert) — Kind host only

Requires Kind am-dev-apps up on this host once.
Token SoT: kube-system/argocd-manager-long-lived-token (or TokenRequest for argocd-manager).
"""
from __future__ import annotations

import base64
import copy
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import yaml

ASRAX = Path.home() / ".asrax"
OUT = ASRAX / "kubeconfig.dev"
OUT_LOCAL = ASRAX / "kubeconfig.dev.local"
TUNNEL = "https://kubeapi-dev.asrax.in"
LOCAL_SERVER = "https://127.0.0.1:6444"
SA_NS = "kube-system"
SA_NAME = "argocd-manager"
TOKEN_SECRET = "argocd-manager-long-lived-token"


def run(argv: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(argv, check=True, text=True, capture_output=True, **kw)


def kind_export() -> dict:
    tmp = Path("/tmp") if sys.platform != "win32" else Path.home() / "AppData" / "Local" / "Temp"
    tmp.mkdir(parents=True, exist_ok=True)
    path = tmp / "am-dev-apps.kind.yaml"
    run(["kind", "export", "kubeconfig", "--name", "am-dev-apps", "--kubeconfig", str(path)])
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    for c in data.get("clusters") or []:
        cl = c.setdefault("cluster", {})
        cl["server"] = LOCAL_SERVER
    return data


def read_token(local_kc: Path) -> str:
    try:
        b64 = run(
            [
                "kubectl",
                "--kubeconfig",
                str(local_kc),
                "-n",
                SA_NS,
                "get",
                "secret",
                TOKEN_SECRET,
                "-o",
                "jsonpath={.data.token}",
            ]
        ).stdout.strip()
        if b64:
            return base64.b64decode(b64).decode()
    except subprocess.CalledProcessError:
        pass
    return run(
        [
            "kubectl",
            "--kubeconfig",
            str(local_kc),
            "-n",
            SA_NS,
            "create",
            "token",
            SA_NAME,
            "--duration=8760h",
        ]
    ).stdout.strip()


def dump(path: Path, cfg: dict) -> None:
    path.write_text(yaml.safe_dump(cfg, default_flow_style=False, sort_keys=False), encoding="utf-8")


def main() -> int:
    ASRAX.mkdir(parents=True, exist_ok=True)
    kind = kind_export()
    local_cluster = copy.deepcopy(kind["clusters"][0])
    local_cluster["name"] = "kind-am-dev-apps-local"
    local_user = copy.deepcopy(kind["users"][0])
    local_user["name"] = "kind-am-dev-apps-local"

    local_cfg = {
        "apiVersion": "v1",
        "kind": "Config",
        "preferences": {},
        "clusters": [local_cluster],
        "users": [local_user],
        "contexts": [
            {
                "name": "dev-apps-local",
                "context": {
                    "cluster": "kind-am-dev-apps-local",
                    "user": "kind-am-dev-apps-local",
                },
            }
        ],
        "current-context": "dev-apps-local",
    }
    dump(OUT_LOCAL, local_cfg)
    token = read_token(OUT_LOCAL)

    if OUT.exists():
        bak = ASRAX / f"kubeconfig.dev.bak-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
        shutil.copy2(OUT, bak)
        print(f"backup {bak}")

    tunnel_cfg = {
        "apiVersion": "v1",
        "kind": "Config",
        "preferences": {},
        "clusters": [
            {
                "name": "kind-am-dev-apps",
                "cluster": {
                    "server": TUNNEL,
                    "insecure-skip-tls-verify": True,
                },
            }
        ],
        "users": [{"name": "kind-am-dev-apps", "user": {"token": token}}],
        "contexts": [
            {
                "name": "dev-apps",
                "context": {"cluster": "kind-am-dev-apps", "user": "kind-am-dev-apps"},
            }
        ],
        "current-context": "dev-apps",
    }
    dump(OUT, tunnel_cfg)
    print(f"wrote {OUT} -> {TUNNEL} (bearer)")
    print(f"wrote {OUT_LOCAL} -> {LOCAL_SERVER} (client-cert, Kind host only)")

    for path, label in ((OUT, "tunnel"), (OUT_LOCAL, "local")):
        r = subprocess.run(
            ["kubectl", "--kubeconfig", str(path), "get", "ns"],
            capture_output=True,
            text=True,
            timeout=60,
        )
        print(f"probe {label}: rc={r.returncode}")
        if r.returncode != 0:
            print((r.stderr or r.stdout)[:400])
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
