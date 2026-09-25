#!/usr/bin/env python3
"""One-shot: sync Keycloak admin → credentials env + Vault am-identity, roll pods, run 4d gate.

Intended as the durable finish path for phase-4d (not a disposable tmp-p4 script).
  PYTHONPATH=scripts/kind-fleet python scripts/kind-fleet/sync_keycloak_admin_to_vault.py --env prod
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--env", choices=("prod", "dev"), default="prod")
    args = p.parse_args()
    if args.env != "prod":
        print("dev: use platform write_keycloak_admin_env + vault-apps apply", file=sys.stderr)
        return 2

    kube_platform = "/data/am-state/kubeconfig.am-prod-platform.yaml"
    kube_infra = "/data/am-state/kubeconfig.am-prod-infra.yaml"
    kube_apps = "/data/am-state/kubeconfig.am-prod-apps.yaml"
    out_env = Path("/data/am-state/credentials/prod-keycloak-admin.env")
    vault_keys = Path("/data/am-state/vault-prod-infra.json")

    user = subprocess.check_output(
        [
            "kubectl",
            "--kubeconfig",
            kube_platform,
            "-n",
            "identity",
            "get",
            "secret",
            "keycloak-admin",
            "-o",
            "jsonpath={.data.username}",
        ],
        text=True,
    ).strip()
    user = base64.b64decode(user).decode() if user else "admin"
    pw = base64.b64decode(
        subprocess.check_output(
            [
                "kubectl",
                "--kubeconfig",
                kube_platform,
                "-n",
                "identity",
                "get",
                "secret",
                "keycloak-admin",
                "-o",
                "jsonpath={.data.password}",
            ],
            text=True,
        ).strip()
    ).decode()
    out_env.parent.mkdir(parents=True, exist_ok=True)
    out_env.write_text(
        f"KEYCLOAK_ADMIN_USER={user}\nKEYCLOAK_ADMIN_PASSWORD={pw}\nKEYCLOAK_REALM=am-realm\n",
        encoding="ascii",
    )
    os.chmod(out_env, 0o600)
    print(f"wrote {out_env} user={user} pass_len={len(pw)}")

    root = json.loads(vault_keys.read_text(encoding="utf-8-sig"))["root_token"]
    vp = subprocess.check_output(
        [
            "kubectl",
            "--kubeconfig",
            kube_infra,
            "-n",
            "vault",
            "get",
            "pod",
            "-l",
            "app.kubernetes.io/name=vault",
            "-o",
            "jsonpath={.items[0].metadata.name}",
        ],
        text=True,
    ).strip()
    # Patch via vault CLI inside pod (HTTPS root write can 403 on this fleet).
    patch = (
        f"export VAULT_TOKEN='{root}'; export VAULT_ADDR=http://127.0.0.1:8200; "
        f"vault kv patch apps/prod/services/am-identity "
        f"KEYCLOAK_ADMIN_USER='{user}' KEYCLOAK_ADMIN_PASSWORD='{pw}' "
        f"KEYCLOAK_URL='https://auth.asrax.in' KEYCLOAK_REALM='am-realm' "
        f"OIDC_ISSUER='https://auth.asrax.in/realms/am-realm'"
    )
    subprocess.check_call(
        ["kubectl", "--kubeconfig", kube_infra, "-n", "vault", "exec", vp, "--", "sh", "-c", patch]
    )
    print("vault patched apps/prod/services/am-identity")

    subprocess.check_call(
        [
            "kubectl",
            "--kubeconfig",
            kube_apps,
            "-n",
            "am-apps-prod",
            "rollout",
            "restart",
            "deploy/am-identity-prod",
        ]
    )
    # Delete old RS pods so traffic is not sticky on stale env
    subprocess.call(
        [
            "kubectl",
            "--kubeconfig",
            kube_apps,
            "-n",
            "am-apps-prod",
            "delete",
            "pod",
            "-l",
            "app.kubernetes.io/instance=am-identity-prod",
            "--wait=false",
        ]
    )
    subprocess.check_call(
        [
            "kubectl",
            "--kubeconfig",
            kube_apps,
            "-n",
            "am-apps-prod",
            "rollout",
            "status",
            "deploy/am-identity-prod",
            "--timeout=300s",
        ]
    )
    # Confirm env length in a Ready pod
    pod = subprocess.check_output(
        [
            "kubectl",
            "--kubeconfig",
            kube_apps,
            "-n",
            "am-apps-prod",
            "get",
            "pods",
            "-l",
            "app.kubernetes.io/instance=am-identity-prod",
            "--field-selector=status.phase=Running",
            "-o",
            "jsonpath={.items[0].metadata.name}",
        ],
        text=True,
    ).strip()
    env_out = subprocess.check_output(
        [
            "kubectl",
            "--kubeconfig",
            kube_apps,
            "-n",
            "am-apps-prod",
            "exec",
            pod,
            "--",
            "sh",
            "-c",
            'echo admin_pass_len=${#KEYCLOAK_ADMIN_PASSWORD}',
        ],
        text=True,
    ).strip()
    print(pod, env_out)
    if f"admin_pass_len={len(pw)}" not in env_out:
        print(f"WARN expected admin_pass_len={len(pw)} got {env_out}", file=sys.stderr)

    # Run phase gate 4d
    env = os.environ.copy()
    root_repo = Path(__file__).resolve().parents[2]
    env["PYTHONPATH"] = str(root_repo / "scripts" / "kind-fleet")
    r = subprocess.run(
        [sys.executable, "-m", "phase_gates", "--env", "prod", "--wave", "4d"],
        cwd=str(root_repo),
        env=env,
    )
    return r.returncode


if __name__ == "__main__":
    raise SystemExit(main())
