#!/usr/bin/env bash
# Post-restart: refresh all infra Endpoints labeled am.io/bridge=cross-cluster
# to the live Kind node IP from Docker DNS (am.io/backend-host).
#
# Covers *-platform bridges and apps-traefik-bridge. Safe to re-run.
#
# Usage:
#   ENV=prod ./refresh-cross-cluster-bridges.sh
#   ./refresh-cross-cluster-bridges.sh prod
set -euo pipefail

ENV_NAME="${1:-${ENV:-prod}}"
case "$ENV_NAME" in
  dev|preprod|prod|dr) ;;
  *) echo "ENV must be dev|preprod|prod|dr (got: $ENV_NAME)" >&2; exit 1 ;;
esac

NAMESPACE="${NAMESPACE:-infra}"
ASRAX_HOME="${ASRAX_HOME:-${HOME:-/root}/.asrax}"
INFRA_KUBECONFIG="${INFRA_KUBECONFIG:-${ASRAX_HOME}/kubeconfig.am-${ENV_NAME}-infra.yaml}"

if [[ ! -f "$INFRA_KUBECONFIG" ]]; then
  echo "missing kubeconfig $INFRA_KUBECONFIG" >&2
  exit 1
fi

# Contabo/Kind: kubeconfig may point at a stale API URL — rewrite to live infra CP Docker IP.
INFRA_CP="am-${ENV_NAME}-infra-control-plane"
if docker inspect "$INFRA_CP" >/dev/null 2>&1; then
  CP_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$INFRA_CP" | awk '{print $1}')
  OUT="/tmp/kubeconfig.am-${ENV_NAME}-infra.bridges.yaml"
  python3 - "$INFRA_KUBECONFIG" "$CP_IP" "$OUT" <<'PY'
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
  INFRA_KUBECONFIG="$OUT"
fi

export ENV_NAME NAMESPACE INFRA_KUBECONFIG

exec python3 - <<'PY'
import json, os, subprocess, sys, tempfile

env = os.environ["ENV_NAME"]
ns = os.environ["NAMESPACE"]
kube = os.environ["INFRA_KUBECONFIG"]

def run(cmd, check=True, capture=True):
    r = subprocess.run(cmd, check=check, capture_output=capture, text=True)
    return r.stdout.strip() if capture else ""

def docker_ip(host):
    if not host or host == "static-ip":
        return None
    try:
        out = run([
            "docker", "inspect", "-f",
            "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}",
            host,
        ])
    except subprocess.CalledProcessError:
        return None
    ip = (out or "").splitlines()[0].strip() if out else ""
    return ip or None

def resolve_backend_host(name, label_host):
    if label_host and label_host != "static-ip":
        return label_host
    if name == "apps-traefik-bridge":
        return f"am-{env}-apps-control-plane"
    if name.endswith("-platform"):
        return f"am-{env}-platform-control-plane"
    return None

def is_bridge(name, bridge_label):
    return (
        bridge_label == "cross-cluster"
        or name == "apps-traefik-bridge"
        or name.endswith("-platform")
    )

raw = run(["kubectl", "--kubeconfig", kube, "-n", ns, "get", "endpoints",
           "-l", "am.io/bridge=cross-cluster", "-o", "json"], check=False)
try:
    data = json.loads(raw) if raw else {"items": []}
except json.JSONDecodeError:
    data = {"items": []}
if not data.get("items"):
    data = json.loads(run(["kubectl", "--kubeconfig", kube, "-n", ns,
                           "get", "endpoints", "-o", "json"]))

ip_cache = {}
patched = ok = skipped = 0

for ep in data.get("items") or []:
    md = ep.get("metadata") or {}
    name = md.get("name") or ""
    labels = dict(md.get("labels") or {})
    bridge = labels.get("am.io/bridge") or ""
    if not is_bridge(name, bridge):
        continue

    backend_host = resolve_backend_host(name, labels.get("am.io/backend-host") or "")
    if not backend_host or backend_host == "static-ip":
        print(f"skip {name} (static-ip or unknown backend-host)")
        skipped += 1
        continue

    if backend_host not in ip_cache:
        ip_cache[backend_host] = docker_ip(backend_host)
    ip = ip_cache[backend_host]
    if not ip:
        print(f"warning: skip {name}: docker inspect failed for {backend_host}", file=sys.stderr)
        skipped += 1
        continue

    subsets = ep.get("subsets") or []
    if not subsets or not (subsets[0].get("ports") or []):
        print(f"warning: skip {name} (no subsets/ports)", file=sys.stderr)
        skipped += 1
        continue
    port = subsets[0]["ports"][0]["port"]
    port_name = subsets[0]["ports"][0].get("name") or "http"
    addrs = subsets[0].get("addresses") or []
    old = addrs[0].get("ip") if addrs else None
    if old == ip:
        print(f"ok {name} already {ip}:{port} (host={backend_host})")
        ok += 1
        continue

    labels["am.io/bridge"] = "cross-cluster"
    labels["am.io/backend-host"] = backend_host
    doc = {
        "apiVersion": "v1",
        "kind": "Endpoints",
        "metadata": {"name": name, "namespace": ns, "labels": labels},
        "subsets": [{
            "addresses": [{"ip": ip}],
            "ports": [{"name": port_name, "port": int(port), "protocol": "TCP"}],
        }],
    }
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(doc, f)
        path = f.name
    try:
        subprocess.run(["kubectl", "--kubeconfig", kube, "apply", "-f", path], check=True)
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass
    print(f"patched {name} {old or 'none'} -> {ip}:{port} (host={backend_host})")
    patched += 1

print(f"refresh-cross-cluster-bridges done env={env} patched={patched} ok={ok} skipped={skipped}")
sys.exit(0)
PY
