#!/usr/bin/env python3
import json
import subprocess
import time

KC = r"C:\Users\user\.asrax\kubeconfig.am-vps-nonprod.yaml"


def run(args, check=False):
    return subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace")


def main():
    # Soft-drain Contabo dig root
    r = run(
        [
            "kubectl",
            "--kubeconfig",
            KC,
            "-n",
            "argocd",
            "delete",
            "application",
            "dev-apps-root",
            "--cascade=orphan",
            "--wait=false",
        ]
    )
    print("delete_dev_apps_root", r.returncode, (r.stdout or r.stderr)[:200])

    raw = run(
        ["kubectl", "--kubeconfig", KC, "-n", "argocd", "get", "applications.argoproj.io", "-o", "json"]
    ).stdout
    items = json.loads(raw).get("items") or []

    # Delete orphan *-dev again
    for it in items:
        name = it["metadata"]["name"]
        dest = (it.get("spec") or {}).get("destination") or {}
        if dest.get("name") == "am-dev-apps" or (
            name.endswith("-dev") and "preprod" not in name and name != "dev-apps-root"
        ):
            run(
                [
                    "kubectl",
                    "--kubeconfig",
                    KC,
                    "-n",
                    "argocd",
                    "delete",
                    "application",
                    name,
                    "--cascade=orphan",
                    "--wait=false",
                ]
            )
            print("deleted", name)

    # Hard refresh + sync request via annotation for preprod apps
    raw = run(
        ["kubectl", "--kubeconfig", KC, "-n", "argocd", "get", "applications.argoproj.io", "-o", "json"]
    ).stdout
    items = json.loads(raw).get("items") or []
    preprod = [
        it["metadata"]["name"]
        for it in items
        if "preprod" in it["metadata"]["name"] and "root" not in it["metadata"]["name"]
    ]
    print("preprod_apps", len(preprod))
    for name in preprod:
        # Initiate sync via Argo CD API annotation pattern used by CLI
        patch = {
            "metadata": {"annotations": {"argocd.argoproj.io/refresh": "hard"}},
            "operation": {
                "initiatedBy": {"username": "admin"},
                "sync": {"revision": "HEAD", "syncStrategy": {"hook": {}}},
            },
        }
        run(
            [
                "kubectl",
                "--kubeconfig",
                KC,
                "-n",
                "argocd",
                "patch",
                "application",
                name,
                "--type",
                "merge",
                "-p",
                json.dumps(patch),
            ]
        )
    print("patched_sync", len(preprod))
    time.sleep(20)

    raw = run(
        ["kubectl", "--kubeconfig", KC, "-n", "argocd", "get", "application", "am-api-gateway-preprod", "-o", "json"]
    ).stdout
    app = json.loads(raw)
    print(
        "api-gateway",
        app.get("status", {}).get("sync", {}).get("status"),
        app.get("status", {}).get("health", {}).get("status"),
        (app.get("status") or {}).get("operationState", {}).get("phase"),
    )
    # Find vault overlay in desired manifest sources
    srcs = (app.get("spec") or {}).get("sources") or []
    for s in srcs:
        helm = s.get("helm") or {}
        vfs = helm.get("valueFiles") or []
        if vfs:
            print("valueFiles", vfs)

    spc = run(
        [
            "kubectl",
            "--kubeconfig",
            KC,
            "-n",
            "am-apps-preprod",
            "get",
            "secretproviderclass",
            "am-api-gateway-preprod-vault-secrets",
            "-o",
            "json",
        ]
    )
    if spc.returncode == 0:
        sp = json.loads(spc.stdout)
        params = (sp.get("spec") or {}).get("parameters") or {}
        print(
            "spc",
            params.get("vaultAddress"),
            params.get("vaultAuthMountPath"),
            params.get("roleName"),
        )


if __name__ == "__main__":
    main()
