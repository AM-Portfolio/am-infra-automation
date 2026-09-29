#!/usr/bin/env bash
# Point Kind apps-cluster CoreDNS at live am-port-exposer for store/Temporal FQDNs.
# SoT for names: CoreDNS hosts plugin (refreshed here). Never bake 172.18.x into gitops.
#
# Usage:
#   ENV=prod ./refresh-exposer-coredns.sh
#   ./refresh-exposer-coredns.sh prod
set -euo pipefail

ENV_NAME="${1:-${ENV:-prod}}"
case "$ENV_NAME" in
  preprod|prod|dr) ;;
  *) echo "ENV must be preprod|prod|dr (got: $ENV_NAME)" >&2; exit 1 ;;
esac

EXPOSER_NAME="${EXPOSER_NAME:-am-port-exposer}"
ASRAX_HOME="${ASRAX_HOME:-${HOME:-/root}/.asrax}"
DOMAIN="${DOMAIN:-asrax.in}"
export HOME="${HOME:-/root}"
export ENV="$ENV_NAME"

EXPOSER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$EXPOSER_NAME" 2>/dev/null || true)
if [[ -z "$EXPOSER_IP" ]]; then
  echo "ERROR: $EXPOSER_NAME not running / no IP" >&2
  exit 1
fi

case "$ENV_NAME" in
  prod)
    HOSTS=(
      "redis.${DOMAIN}" "mongodb.${DOMAIN}" "mongo.${DOMAIN}" "postgres.${DOMAIN}"
      "kafka.${DOMAIN}" "influxdb.${DOMAIN}" "minio.${DOMAIN}"
      "temporal-rpc-prod.${DOMAIN}"
    )
    ;;
  dr)
    HOSTS=(
      "redis-dr.${DOMAIN}" "mongodb-dr.${DOMAIN}" "mongo-dr.${DOMAIN}" "postgres-dr.${DOMAIN}"
      "kafka-dr.${DOMAIN}" "influxdb-dr.${DOMAIN}" "minio-dr.${DOMAIN}"
      "temporal-rpc-dr.${DOMAIN}"
    )
    ;;
  preprod)
    HOSTS=(
      "redis.${DOMAIN}" "mongodb.${DOMAIN}" "mongo.${DOMAIN}" "postgres.${DOMAIN}"
      "kafka.${DOMAIN}" "influxdb.${DOMAIN}" "minio.${DOMAIN}"
      "temporal-rpc-preprod.${DOMAIN}"
    )
    ;;
esac

APPS_CP="am-${ENV_NAME}-apps-control-plane"
SRC="$ASRAX_HOME/kubeconfig.am-${ENV_NAME}-apps.yaml"
OUT="/tmp/kubeconfig.am-${ENV_NAME}-apps.coredns.yaml"
if [[ ! -f "$SRC" ]]; then
  echo "ERROR: missing kubeconfig $SRC" >&2
  exit 1
fi
if ! docker inspect "$APPS_CP" >/dev/null 2>&1; then
  echo "ERROR: missing Kind node $APPS_CP" >&2
  exit 1
fi

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
    raise SystemExit(f"no API for {ip}")
PY
export KUBECONFIG="$OUT"

HOSTS_LINE="$EXPOSER_IP ${HOSTS[*]}"
export HOSTS_LINE ENV_NAME EXPOSER_IP

python3 <<'PY'
import os, re, subprocess, sys, tempfile

hosts_line = os.environ["HOSTS_LINE"]
env = os.environ["ENV_NAME"]
exposer = os.environ["EXPOSER_IP"]
marker_begin = f"# BEGIN am-exposer-hosts env={env}"
marker_end = f"# END am-exposer-hosts env={env}"

def run(cmd, check=True, input=None):
    r = subprocess.run(cmd, check=check, capture_output=True, text=True, input=input)
    return r.stdout

cm = run(["kubectl", "-n", "kube-system", "get", "configmap", "coredns", "-o", "json"])
import json
doc = json.loads(cm)
corefile = doc["data"]["Corefile"]

block = f"""{marker_begin}
    hosts {{
        {hosts_line}
        fallthrough
    }}
{marker_end}"""

pat = re.compile(
    re.escape(marker_begin) + r".*?" + re.escape(marker_end),
    re.DOTALL,
)

if pat.search(corefile):
    new_core = pat.sub(block, corefile)
else:
    # Insert hosts plugin before the first "forward " in the main server block.
    m = re.search(r"(^[ \t]*forward[ \t]+)", corefile, re.MULTILINE)
    if not m:
        print("ERROR: no forward plugin in Corefile to anchor hosts insert", file=sys.stderr)
        sys.exit(1)
    insert = block + "\n    "
    new_core = corefile[: m.start()] + insert + corefile[m.start() :]

if new_core == corefile:
    print(f"coredns hosts already ok exposer={exposer} env={env}")
    sys.exit(0)

# Apply via kubectl patch of data.Corefile
patch = json.dumps({"data": {"Corefile": new_core}})
with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
    f.write(patch)
    path = f.name
try:
    run(["kubectl", "-n", "kube-system", "patch", "configmap", "coredns", "--type", "merge", "--patch-file", path])
finally:
    os.unlink(path)

print(f"patched kube-system/coredns hosts -> {exposer} ({env})")
# Force reload (Kind CoreDNS reload may lag)
run(["kubectl", "-n", "kube-system", "rollout", "restart", "deployment/coredns"], check=False)
run(["kubectl", "-n", "kube-system", "rollout", "status", "deployment/coredns", "--timeout=90s"], check=False)
print(f"refresh-exposer-coredns done env={env} exposer={exposer}")
PY
