#!/usr/bin/env bash
# Point Kind CoreDNS at live am-port-exposer for store/Temporal FQDNs.
# Patches BOTH apps and infra clusters (Keycloak/Vault live on infra).
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

HOSTS_LINE="$EXPOSER_IP ${HOSTS[*]}"
export HOSTS_LINE ENV_NAME EXPOSER_IP

patch_cluster() {
  local role="$1" # apps|infra
  local CP="am-${ENV_NAME}-${role}-control-plane"
  local SRC="$ASRAX_HOME/kubeconfig.am-${ENV_NAME}-${role}.yaml"
  local OUT="/tmp/kubeconfig.am-${ENV_NAME}-${role}.coredns.yaml"

  if [[ ! -f "$SRC" ]]; then
    echo "WARN: missing kubeconfig $SRC — skip ${role}"
    return 0
  fi
  if ! docker inspect "$CP" >/dev/null 2>&1; then
    echo "WARN: missing Kind node $CP — skip ${role}"
    return 0
  fi

  local CP_IP
  CP_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$CP" | awk '{print $1}')
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
  echo "== CoreDNS exposer hosts on ${ENV_NAME}-${role} (exposer=$EXPOSER_IP) =="
  CLUSTER_ROLE="$role" python3 <<'PY'
import os, re, subprocess, sys, tempfile, json

hosts_line = os.environ["HOSTS_LINE"]
env = os.environ["ENV_NAME"]
exposer = os.environ["EXPOSER_IP"]
role = os.environ.get("CLUSTER_ROLE", "apps")
marker_begin = f"# BEGIN am-exposer-hosts env={env}"
marker_end = f"# END am-exposer-hosts env={env}"

def run(cmd, check=True, input=None):
    r = subprocess.run(cmd, check=check, capture_output=True, text=True, input=input)
    return r.stdout

cm = run(["kubectl", "-n", "kube-system", "get", "configmap", "coredns", "-o", "json"])
doc = json.loads(cm)
corefile = doc["data"]["Corefile"]

# One-line health { lameduck Ns } crashes CoreDNS — normalize before other edits.
corefile = re.sub(
    r"(?m)^([ \t]*)health[ \t]*\{[ \t]*lameduck[ \t]+([^}]+)\}[ \t]*$",
    r"\1health {\n\1   lameduck \2\n\1}",
    corefile,
)

# CoreDNS allows hosts only once per server block — strip markers + any hosts{} first.
corefile = re.sub(
    re.escape(marker_begin) + r".*?" + re.escape(marker_end) + r"\n?",
    "",
    corefile,
    flags=re.DOTALL,
)
corefile = re.sub(r"(?m)^[ \t]*hosts\s*\{.*?^[ \t]*\}\n?", "", corefile, flags=re.DOTALL)

block = f"""{marker_begin}
    hosts {{
        {hosts_line}
        fallthrough
    }}
{marker_end}"""

m = re.search(r"(^[ \t]*forward[ \t]+)", corefile, re.MULTILINE)
if not m:
    print(f"ERROR: no forward plugin in Corefile ({role})", file=sys.stderr)
    sys.exit(1)
new_core = corefile[: m.start()] + block + "\n    " + corefile[m.start() :]

dns1 = os.environ.get("AM_DOCKER_DNS1", "8.8.8.8")
dns2 = os.environ.get("AM_DOCKER_DNS2", "8.8.4.4")
fwd_pat = re.compile(
    r"(^[ \t]*)forward[ \t]+\.[ \t]+[^\n{]*(?:\{[^{}]*\})?",
    re.MULTILINE,
)

def _fwd_repl(m):
    indent = m.group(1)
    return f"{indent}forward . {dns1} {dns2} {{\n{indent}   max_concurrent 1000\n{indent}}}"

new_core2, fwd_n = fwd_pat.subn(_fwd_repl, new_core, count=1)
if fwd_n:
    new_core = new_core2

if new_core == corefile:
    print(f"coredns hosts+forward already ok exposer={exposer} env={env} role={role}")
    sys.exit(0)

patch = json.dumps({"data": {"Corefile": new_core}})
with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
    f.write(patch)
    path = f.name
try:
    run(["kubectl", "-n", "kube-system", "patch", "configmap", "coredns", "--type", "merge", "--patch-file", path])
finally:
    os.unlink(path)

print(f"patched kube-system/coredns hosts -> {exposer} ({env}/{role}); forward . {dns1} {dns2}")
run(["kubectl", "-n", "kube-system", "rollout", "restart", "deployment/coredns"], check=False)
run(["kubectl", "-n", "kube-system", "rollout", "status", "deployment/coredns", "--timeout=90s"], check=False)
print(f"refresh-exposer-coredns done env={env} role={role} exposer={exposer}")
PY
}

patch_cluster apps
patch_cluster infra
echo "refresh-exposer-coredns ALL done env=$ENV_NAME exposer=$EXPOSER_IP"
