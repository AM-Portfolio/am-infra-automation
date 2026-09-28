#!/usr/bin/env python3
import json
import subprocess

kc = r"C:\Users\user\.asrax\kubeconfig.am-vps-nonprod.yaml"
raw = subprocess.check_output(
    ["kubectl", "--kubeconfig", kc, "-n", "argocd", "get", "applications.argoproj.io", "-o", "json"],
    text=True,
)
items = json.loads(raw).get("items") or []
print("total_apps", len(items))
print("=== dig Contabo ===")
for it in items:
    name = it["metadata"]["name"]
    dest = (it.get("spec") or {}).get("destination") or {}
    ns = dest.get("namespace", "")
    server = dest.get("name") or dest.get("server", "")
    if ns in ("am-apps-dev", "am-agents-dev") or name.endswith("-dev"):
        st = (it.get("status") or {}).get("sync", {}).get("status")
        h = (it.get("status") or {}).get("health", {}).get("status")
        print(f"{name} -> {server}/{ns} sync={st} health={h}")
print("=== preprod ===")
for it in items:
    name = it["metadata"]["name"]
    dest = (it.get("spec") or {}).get("destination") or {}
    ns = dest.get("namespace", "")
    if "preprod" in ns or "preprod" in name:
        print(f"{name} -> {dest.get('name')}/{ns}")
print("=== applicationsets ===")
raw2 = subprocess.check_output(
    ["kubectl", "--kubeconfig", kc, "-n", "argocd", "get", "applicationsets.argoproj.io", "-o", "name"],
    text=True,
)
print(raw2)
