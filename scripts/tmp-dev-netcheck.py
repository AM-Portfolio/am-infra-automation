#!/usr/bin/env python3
"""Network gate: TCP reach Contabo Vault/stores from a dig Kind pod (no hostAliases)."""
import subprocess, os, sys, json, time

kc = os.path.expanduser("~/.asrax/kubeconfig.am-dev-apps.yaml")
targets = [
    ("vault.asrax.in", "443"),
    ("mongo.asrax.in", "27017"),
    ("redis.asrax.in", "6379"),
    ("postgres.asrax.in", "5432"),
    ("kafka.asrax.in", "9092"),
]
script = "set -e; " + "; ".join(
    f'echo -n "{h}:{p}="; (nc -z -w 5 {h} {p} && echo OK) || echo FAIL'
    for h, p in targets
)
# Use busybox for nc
cmd = [
    "kubectl", "--kubeconfig", kc, "-n", "am-apps-dev",
    "run", "netcheck-am", "--rm", "-i", "--restart=Never",
    "--image=busybox:1.36", "--command", "--", "sh", "-c", script,
]
print("running netcheck...")
r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
print(r.stdout)
print(r.stderr[-800:] if r.stderr else "")
sys.exit(0 if "FAIL" not in (r.stdout or "") else 1)
