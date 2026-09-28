#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
python3 <<'PY'
import yaml, json
from pathlib import Path
kc = yaml.safe_load(Path("/data/am-state/kubeconfig.am-dr-apps.yaml").read_text())
print(json.dumps({
  "clusters": [{k: ("<redacted>" if "data" in k.lower() or "cert" in k.lower() else v) for k,v in c["cluster"].items()} for c in kc["clusters"]],
  "users_keys": [list(u["user"].keys()) for u in kc["users"]],
  "contexts": kc.get("contexts"),
}, indent=2))
# show if client cert exists under any key
u = kc["users"][0]["user"]
for k in u:
  v=u[k]
  if isinstance(v,str):
    print(k, "len", len(v), "prefix", v[:20])
  else:
    print(k, type(v), v)
PY
