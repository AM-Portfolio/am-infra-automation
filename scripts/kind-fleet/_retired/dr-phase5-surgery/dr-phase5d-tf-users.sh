#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
cd /opt/am-infra-automation/terraform/kind-fleet/dr/platform
python3 <<'PY'
import json, subprocess
state = json.loads(subprocess.check_output(["terraform", "state", "pull"]))
for rsrc in state.get("resources", []):
    mod = rsrc.get("module") or ""
    if "keycloak" in mod or "test_user" in rsrc.get("name",""):
        print(rsrc.get("mode"), rsrc.get("type"), rsrc.get("name"), "module=", mod, "n=", len(rsrc.get("instances") or []))
        for inst in (rsrc.get("instances") or [])[:5]:
            print("  index_key=", inst.get("index_key"), "attr_keys=", list((inst.get("attributes") or {}).keys())[:12])
PY
# also list state addresses
terraform state list | grep -iE 'test_user|password|keycloak' | head -40
