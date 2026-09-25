#!/bin/bash
set -euo pipefail
cd /tmp/kind-fleet
python3 - <<'PY'
import sys
sys.path.insert(0, ".")
from phase_gates import gate_4g_remaining, _env_defaults
cfg = _env_defaults("prod")
cfg["_env"] = "prod"
gate_4g_remaining(cfg)
print("GATE_4G_OK")
PY
