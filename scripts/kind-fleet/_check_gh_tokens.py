from pathlib import Path
import json
import urllib.request
import urllib.error

vals = {}
for line in Path.home().joinpath(".asrax/credentials.env").read_text(encoding="utf-8-sig").splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, _, v = line.partition("=")
    vals[k.strip()] = v.strip().strip("\"'")

for key in ("GITHUB_TOKEN", "GHCR_TOKEN"):
    t = vals.get(key, "")
    if not t:
        print(key, "missing")
        continue
    req = urllib.request.Request(
        "https://api.github.com/user",
        headers={
            "Authorization": f"Bearer {t}",
            "User-Agent": "am-dr",
            "Accept": "application/vnd.github+json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            d = json.load(r)
            print(key, "OK", d.get("login"), "scopes", r.headers.get("X-OAuth-Scopes"))
    except urllib.error.HTTPError as e:
        print(key, "FAIL", e.code, e.read()[:200])
    except Exception as e:
        print(key, "FAIL", type(e).__name__, str(e)[:120])
