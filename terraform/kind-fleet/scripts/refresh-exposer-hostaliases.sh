#!/usr/bin/env bash
# Refresh apps/agents hostAliases IP to current am-port-exposer Docker IP.
set -euo pipefail

ENV="${ENV:-prod}"
EXPOSER_NAME="${EXPOSER_NAME:-am-port-exposer}"
ASRAX_HOME="${ASRAX_HOME:-${HOME:-/root}/.asrax}"
export HOME="${HOME:-/root}"

EXPOSER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$EXPOSER_NAME" 2>/dev/null || true)
if [[ -z "$EXPOSER_IP" ]]; then
  echo "ERROR: $EXPOSER_NAME not running / no IP" >&2
  exit 1
fi

APPS_CP="am-${ENV}-apps-control-plane"
SRC="$ASRAX_HOME/kubeconfig.am-${ENV}-apps.yaml"
OUT="/tmp/kubeconfig.am-${ENV}-apps.exposer.yaml"
CP_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$APPS_CP" | awk '{print $1}')
python3 - "$SRC" "$CP_IP" "$OUT" <<'PY'
import re, socket, sys
src, ip, dst = sys.argv[1], sys.argv[2], sys.argv[3]
t = open(src).read()
for port in (6443, 6444):
    try:
        s = socket.create_connection((ip, port), 2); s.close()
        open(dst, "w").write(re.sub(r"(https?://)[^\s]+", f"https://{ip}:{port}", t, count=1))
        break
    except OSError:
        pass
else:
    raise SystemExit(f"no API for {dst}")
PY
export KUBECONFIG="$OUT"

kubectl get deploy,sts -A -o json > /tmp/ha-workloads.json
python3 - "$EXPOSER_IP" <<'PY'
import json, sys, subprocess
new = sys.argv[1]
doc = json.load(open("/tmp/ha-workloads.json"))
patched = skipped = 0
markers = (
    "redis.asrax.in", "mongodb.asrax.in", "mongo.asrax.in", "postgres.asrax.in",
    "kafka.asrax.in", "temporal-rpc-prod.asrax.in", "temporal-rpc-dr.asrax.in",
    "temporal-rpc-preprod.asrax.in",
    "redis-dr.asrax.in", "mongodb-dr.asrax.in", "postgres-dr.asrax.in", "kafka-dr.asrax.in",
)
for i in doc.get("items", []):
    kind = i["kind"]
    ns = i["metadata"]["namespace"]
    name = i["metadata"]["name"]
    ha = (i.get("spec") or {}).get("template", {}).get("spec", {}).get("hostAliases") or []
    if not ha:
        continue
    relevant = any(
        any(h in markers or str(h).endswith(".asrax.in") for h in (e.get("hostnames") or []))
        for e in ha
    )
    if not relevant:
        continue
    if all(e.get("ip") == new for e in ha):
        skipped += 1
        continue
    for e in ha:
        e["ip"] = new
    k = "deployment" if kind == "Deployment" else "statefulset"
    patch = json.dumps({"spec": {"template": {"spec": {"hostAliases": ha}}}})
    r = subprocess.run(
        ["kubectl", "-n", ns, "patch", k, name, "--type", "merge", "-p", patch],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        print(f"FAIL {ns}/{name}: {r.stderr.strip()}", file=sys.stderr)
    else:
        print(f"patched {ns}/{name} -> {new}")
        patched += 1
print(f"done patched={patched} already_ok={skipped} exposer={new}")
PY
