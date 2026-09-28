#!/usr/bin/env python3
"""Create local Argo session token into ~/.asrax/credentials.d/argocd-dev-local.env"""
import base64, json, os, subprocess, ssl, urllib.request, pathlib

kc = os.path.expanduser("~/.asrax/kubeconfig.am-dev-apps.yaml")

def k(args):
    return subprocess.check_output(["kubectl", "--kubeconfig", kc] + args, text=True).strip()

pw = base64.b64decode(k(["-n", "argocd", "get", "secret", "argocd-initial-admin-secret", "-o", "jsonpath={.data.password}"])).decode()
np = k(["-n", "argocd", "get", "svc", "argocd-server", "-o", "jsonpath={.spec.ports[?(@.port==443)].nodePort}"])

# port-forward in background
pf = subprocess.Popen(
    ["kubectl", "--kubeconfig", kc, "-n", "argocd", "port-forward", "svc/argocd-server", "8088:443"],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
)
import time; time.sleep(2)
ctx = ssl._create_unverified_context()
body = json.dumps({"username": "admin", "password": pw}).encode()
req = urllib.request.Request(
    "https://127.0.0.1:8088/api/v1/session",
    data=body,
    headers={"Content-Type": "application/json"},
    method="POST",
)
with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
    token = json.loads(r.read().decode())["token"]
pf.terminate()
out = pathlib.Path(os.path.expanduser("~/.asrax/credentials.d/argocd-dev-local.env"))
out.write_text(
    f"ARGOCD_SERVER_DEV=https://127.0.0.1:{np}\n"
    f"ARGOCD_AUTH_TOKEN_DEV={token}\n"
    f"# port-forward alternate: https://127.0.0.1:8088\n",
    encoding="utf-8",
)
print("wrote", out, "token_len", len(token), "nodeport", np)
