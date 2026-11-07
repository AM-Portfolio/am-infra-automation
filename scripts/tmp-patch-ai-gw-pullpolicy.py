import json, subprocess, tempfile, os

for app in ("am-ai-gateway-dev", "am-ai-gateway-preprod"):
    raw = subprocess.check_output(["kubectl", "-n", "argocd", "get", "app", app, "-o", "json"])
    doc = json.loads(raw)
    sources = doc["spec"]["sources"]
    helm = sources[0].setdefault("helm", {})
    params = helm.setdefault("parameters", [])
    want = {
        "image.pullPolicy": "IfNotPresent",
        "global.image.pullPolicy": "IfNotPresent",
    }
    by = {p["name"]: p for p in params}
    for k, v in want.items():
        if k in by:
            by[k]["value"] = v
        else:
            params.append({"name": k, "value": v})
    patch = {"spec": {"sources": sources}}
    path = os.path.join(tempfile.gettempdir(), f"{app}-sources.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(patch, f)
    subprocess.check_call(["kubectl", "-n", "argocd", "patch", "app", app, "--type", "merge", "--patch-file", path])
    print("patched", app)
