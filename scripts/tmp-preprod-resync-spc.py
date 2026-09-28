#!/usr/bin/env python3
"""Hard-refresh + sync Contabo preprod Apps until SPC shows vault.asrax.in."""
import json
import subprocess
import time

KC = r"C:\Users\user\.asrax\kubeconfig.am-vps-nonprod.yaml"


def run(args):
    return subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace")


def main():
    raw = run(
        ["kubectl", "--kubeconfig", KC, "-n", "argocd", "get", "applications.argoproj.io", "-o", "json"]
    ).stdout
    names = [
        it["metadata"]["name"]
        for it in json.loads(raw).get("items") or []
        if "preprod" in it["metadata"]["name"] and "root" not in it["metadata"]["name"]
    ]
    patch = {
        "metadata": {"annotations": {"argocd.argoproj.io/refresh": "hard"}},
        "operation": {
            "initiatedBy": {"username": "admin"},
            "sync": {"revision": "HEAD", "syncStrategy": {"hook": {}}},
        },
    }
    for name in names:
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
    print("synced", len(names))
    time.sleep(45)

    # Sample SPCs apps + agents
    samples = [
        ("am-apps-preprod", "am-api-gateway-preprod-vault-secrets"),
        ("am-apps-preprod", "am-identity-preprod-vault-secrets"),
        ("am-apps-preprod", "am-gateway-preprod-vault-secrets"),
        ("am-agents-preprod", "am-mcp-server-preprod-vault-secrets"),
    ]
    for ns, spc in samples:
        r = run(["kubectl", "--kubeconfig", KC, "-n", ns, "get", "secretproviderclass", spc, "-o", "json"])
        if r.returncode != 0:
            print(spc, "MISSING")
            continue
        p = json.loads(r.stdout)["spec"]["parameters"]
        print(spc, p.get("vaultAddress"), p.get("vaultAuthMountPath"), p.get("roleName"))

    pods = run(["kubectl", "--kubeconfig", KC, "-n", "am-agents-preprod", "get", "pods", "--no-headers"])
    print("agents_pods", (pods.stdout or "").strip()[:400] or "none")


if __name__ == "__main__":
    main()
