#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
cd /opt/am-infra-automation
PYTHONPATH=scripts/kind-fleet python3 -m phase_gates --env dr --wave 4d 2>&1 | tee /tmp/dr-phase5d-gate.log | tail -80
