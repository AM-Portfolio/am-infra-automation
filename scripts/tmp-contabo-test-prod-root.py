#!/usr/bin/env python3
import json, pathlib, urllib.request

env = {}
for line in pathlib.Path("/tmp/vault-prod-root.env").read_text().splitlines():
    if "=" in line and not line.strip().startswith("#"):
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
tok = env.get("VAULT_TOKEN") or ""
print("token_len", len(tok), "addr_in_file", env.get("VAULT_ADDR"))

for a in ["https://vault.asrax.in", "http://127.0.0.1:8200"]:
    try:
        with urllib.request.urlopen(a + "/v1/sys/health", timeout=20) as r:
            d = json.loads(r.read().decode())
            print("health", a, d.get("cluster_name"), d.get("cluster_id"))
    except Exception as e:
        print("health FAIL", a, getattr(e, "code", None))


def call(method, url, token=None):
    headers = {}
    if token:
        headers["X-Vault-Token"] = token
    req = urllib.request.Request(url, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())


try:
    d = call("GET", "https://vault.asrax.in/v1/auth/token/lookup-self", tok)
    print(
        "lookup OK policies",
        (d.get("data") or {}).get("policies"),
        "display",
        (d.get("data") or {}).get("display_name"),
    )
except Exception as e:
    body = b""
    if hasattr(e, "read"):
        try:
            body = e.read()
        except Exception:
            pass
    print("lookup FAIL", getattr(e, "code", None), body[:300])

if not tok:
    raise SystemExit(1)

try:
    d = call("GET", "https://vault.asrax.in/v1/sys/auth", tok)
    mounts = d.get("data") or d
    print("auth mounts", list(mounts.keys()) if isinstance(mounts, dict) else mounts)
except Exception as e:
    print("auth FAIL", getattr(e, "code", None))

for path in ("dev", "prod", "preprod"):
    try:
        d = call("LIST", f"https://vault.asrax.in/v1/apps/metadata/{path}", tok)
        keys = (d.get("data") or {}).get("keys") or []
        print(f"{path} keys ({len(keys)})", keys[:20])
    except Exception as e:
        print(f"{path} LIST FAIL", getattr(e, "code", None))
