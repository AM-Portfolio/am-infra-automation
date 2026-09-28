#!/bin/bash
# Emit {"username":"...","secret":"..."} from docker config.json for ghcr.io (or empty).
set -euo pipefail
CFG="${DOCKER_CONFIG:-}/config.json"
if [ ! -f "$CFG" ]; then CFG="$HOME/.docker/config.json"; fi
if [ ! -f "$CFG" ]; then CFG=/root/.docker/config.json; fi
export CFG
python3 - <<'PY'
import json, base64, os, sys
cfg = os.environ.get("CFG", "/root/.docker/config.json")
try:
  d = json.load(open(cfg))
except Exception:
  print('{"username":"","secret":""}')
  sys.exit(0)
auths = d.get("auths") or {}
entry = auths.get("ghcr.io") or auths.get("https://ghcr.io") or {}
user = entry.get("username") or ""
secret = entry.get("password") or entry.get("identitytoken") or ""
if not secret and entry.get("auth"):
  try:
    raw = base64.b64decode(entry["auth"]).decode()
    if ":" in raw:
      user, secret = raw.split(":", 1)
  except Exception:
    pass
def esc(s):
  return s.replace("\\", "\\\\").replace('"', '\\"')
print('{"username":"%s","secret":"%s"}' % (esc(user), esc(secret)))
PY
