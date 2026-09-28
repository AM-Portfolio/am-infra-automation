import os, pathlib, subprocess

p = pathlib.Path(os.path.expanduser("~/.asrax/credentials.env"))
vals = {}
for line in p.read_text(encoding="utf-8", errors="ignore").splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    vals[k.strip()] = v.strip().strip('"').strip("'")
token = vals.get("GITHUB_TOKEN") or vals.get("GH_TOKEN") or vals.get("GITHUB_PAT") or vals.get("GHCR_TOKEN")
user = vals.get("GITHUB_USER") or vals.get("GITHUB_USERNAME") or "x-access-token"
assert token, "missing github token"
kc = os.path.expanduser("~/.asrax/kubeconfig.am-dev-apps.yaml")
manifest = f"""apiVersion: v1
kind: Secret
metadata:
  name: repo-am-portfolio
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo
stringData:
  type: git
  url: https://github.com/AM-Portfolio
  username: {user}
  password: {token}
"""
path = os.path.join(os.environ["TEMP"], "argo-repo.yaml")
open(path, "w", encoding="utf-8").write(manifest)
r = subprocess.run(["kubectl", "--kubeconfig", kc, "apply", "-f", path], capture_output=True, text=True)
print(r.stdout.strip() or r.stderr.strip())
