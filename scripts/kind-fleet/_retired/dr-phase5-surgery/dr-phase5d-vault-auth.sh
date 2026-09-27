#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:/usr/bin:/bin
python3 - <<'PY'
import json,urllib.request
init=json.load(open("/data/am-state/vault-dr-infra.json"))
token=init["root_token"]
addr="https://vault-dr.asrax.in"
# identity lookup
req=urllib.request.Request(f"{addr}/v1/auth/token/lookup-self", headers={"X-Vault-Token":token})
try:
  with urllib.request.urlopen(req, timeout=20) as r:
    d=json.loads(r.read().decode())
  data=d.get("data") or {}
  print("lookup_ok policies=", data.get("policies"), "display=", data.get("display_name"), "ttl=", data.get("ttl"), "orphan=", data.get("orphan"))
except Exception as e:
  print("lookup_fail", e)
# list mounts
req=urllib.request.Request(f"{addr}/v1/sys/mounts", headers={"X-Vault-Token":token})
try:
  with urllib.request.urlopen(req, timeout=20) as r:
    d=json.loads(r.read().decode())
  mounts=sorted([k for k in (d.get("data") or d).keys() if not k.startswith("sys")])
  print("mounts", mounts[:40])
except Exception as e:
  print("mounts_fail", e)
# try read existing apps path that gate 4a passed
req=urllib.request.Request(f"{addr}/v1/apps/data/dr/infra/postgres", headers={"X-Vault-Token":token})
try:
  with urllib.request.urlopen(req, timeout=20) as r:
    d=json.loads(r.read().decode())
  print("postgres_read_ok keys", sorted(((d.get("data") or {}).get("data") or {}).keys())[:8])
except Exception as e:
  print("postgres_read_fail", e)
# try write sys/health
req=urllib.request.Request(f"{addr}/v1/sys/health")
with urllib.request.urlopen(req, timeout=20) as r:
  print("health", r.status)
PY

# how phase_gates finds token
grep -n "vault\|token\|root" /opt/am-infra-automation/scripts/kind-fleet/phase_gates/__init__.py | head -40
ls /data/am-state/seed/ 2>/dev/null | head
ls /opt/am-infra-automation/terraform/kind-fleet/dr/vault-apps/*.tfvars 2>/dev/null
grep -E '^vault_' /opt/am-infra-automation/terraform/kind-fleet/dr/vault-apps/*.auto.tfvars 2>/dev/null | sed 's/=.*/=***/' | head
