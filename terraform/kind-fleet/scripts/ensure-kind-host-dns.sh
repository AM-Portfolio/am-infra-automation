#!/usr/bin/env bash
# Durable Docker + Kind-node + CoreDNS upstream DNS for fleet hosts.
#
# Problem: Kind nodes inherit Docker embedded DNS (bridge gateway, often
# 172.18.0.1) whose ExtServers can be Tailscale MagicDNS (100.100.100.100).
# That breaks ghcr.io / public lookups → ImagePullBackOff ("server misbehaving").
# Host 8.8.8.8 works; bridge DNS does not.
#
# Fix (IP-change resilient — no Kind bridge IPs baked):
#   1) /etc/docker/daemon.json  "dns": ["8.8.8.8","8.8.4.4"]
#   2) Patch each Kind node /etc/resolv.conf to those nameservers
#      (Docker will not overwrite once the file is modified)
#   3) CoreDNS forward . 8.8.8.8 8.8.4.4  (never /etc/resolv.conf)
#
# Usage (root on VPS):
#   ENV=prod bash ensure-kind-host-dns.sh
#   bash ensure-kind-host-dns.sh prod --restart-docker   # after daemon.json change
#   bash ensure-kind-host-dns.sh prod --dry-run
#
# Safe: never kind delete. Docker restart only with --restart-docker.
#
# After Docker restart Kind node IPs often change. Vault auth/kubernetes-apps
# kubernetes_host must be re-pointed at the live apps API IP (Vault pods cannot
# resolve Docker DNS). kind-fleet-boot.sh step 2c runs ensure-vault-k8s-apps-auth.sh;
# or: ENV=prod bash ensure-vault-k8s-apps-auth.sh
set -euo pipefail

ENV_NAME="${ENV:-prod}"
RESTART_DOCKER=0
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --restart-docker) RESTART_DOCKER=1 ;;
    --dry-run) DRY_RUN=1 ;;
    prod|preprod|dr|dev|obs) ENV_NAME="$arg" ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

DNS1="${AM_DOCKER_DNS1:-8.8.8.8}"
DNS2="${AM_DOCKER_DNS2:-8.8.4.4}"
ASRAX_HOME="${ASRAX_HOME:-${HOME:-/root}/.asrax}"
DAEMON_JSON="${DAEMON_JSON:-/etc/docker/daemon.json}"
RESOLV_BODY="# AM kind-host-dns (durable; do not point at Docker bridge)
nameserver ${DNS1}
nameserver ${DNS2}
options ndots:0
"

echo "== ensure-kind-host-dns ENV=$ENV_NAME dns=${DNS1},${DNS2} restart_docker=$RESTART_DOCKER dry_run=$DRY_RUN =="

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: run as root (daemon.json + docker exec on Kind nodes)" >&2
    exit 1
  fi
}

merge_daemon_json() {
  python3 - "$DAEMON_JSON" "$DNS1" "$DNS2" <<'PY'
import json, os, sys
path, d1, d2 = sys.argv[1], sys.argv[2], sys.argv[3]
want = [d1, d2]
doc = {}
if os.path.isfile(path):
    with open(path) as f:
        raw = f.read().strip()
    if raw:
        doc = json.loads(raw)
if not isinstance(doc, dict):
    raise SystemExit(f"daemon.json is not an object: {path}")
cur = doc.get("dns")
changed = cur != want
doc["dns"] = want
print(json.dumps({"path": path, "changed": changed, "dns": doc["dns"], "doc": doc}))
PY
}

apply_daemon_json() {
  need_root
  local meta new_doc
  meta=$(merge_daemon_json)
  echo "daemon.json plan: $meta"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  new_doc=$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])["doc"], indent=2))' "$meta")
  local changed
  changed=$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1])["changed"] else "0")' "$meta")
  if [[ "$changed" -eq 1 ]] || [[ ! -f "$DAEMON_JSON" ]]; then
    umask 022
    printf '%s\n' "$new_doc" >"$DAEMON_JSON"
    echo "wrote $DAEMON_JSON"
  else
    echo "daemon.json already has dns=$DNS1,$DNS2"
  fi
  # Best-effort: allow Kind subnet DNS egress through DOCKER-USER (Tailscale/ts-forward path).
  if iptables -L DOCKER-USER -n >/dev/null 2>&1; then
    iptables -C DOCKER-USER -s 172.18.0.0/16 -p udp --dport 53 -j ACCEPT 2>/dev/null \
      || iptables -I DOCKER-USER 1 -s 172.18.0.0/16 -p udp --dport 53 -j ACCEPT || true
    iptables -C DOCKER-USER -s 172.18.0.0/16 -p tcp --dport 53 -j ACCEPT 2>/dev/null \
      || iptables -I DOCKER-USER 1 -s 172.18.0.0/16 -p tcp --dport 53 -j ACCEPT || true
  fi
  if [[ "$RESTART_DOCKER" -eq 1 ]]; then
    echo "restarting docker (Kind nodes bounce; not kind delete)..."
    systemctl restart docker
    sleep 5
    # wait for kind nodes
    local n=0
    while [[ $n -lt 60 ]]; do
      if docker ps --format '{{.Names}}' | grep -q "am-${ENV_NAME}-apps-control-plane\|am-${ENV_NAME}-infra-control-plane"; then
        break
      fi
      sleep 2
      n=$((n + 1))
    done
  elif [[ "$changed" -eq 1 ]]; then
    echo "NOTE: daemon.json changed but --restart-docker not set."
    echo "      Existing Kind nodes keep old resolv until patched below / next recreate."
    echo "      New containers after a future docker restart will get ${DNS1}/${DNS2}."
  fi
}

patch_kind_node_resolv() {
  need_root
  local nodes
  nodes=$(docker ps --format '{{.Names}}' | grep -E 'control-plane|worker' | sort || true)
  if [[ -z "$nodes" ]]; then
    echo "WARN: no Kind node containers running"
    return 0
  fi
  local n
  for n in $nodes; do
    echo "--- patch resolv $n ---"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      docker exec "$n" cat /etc/resolv.conf || true
      continue
    fi
    # Once modified, Docker Engine will not rewrite resolv.conf on this container.
    printf '%s' "$RESOLV_BODY" | docker exec -i "$n" tee /etc/resolv.conf >/dev/null
    docker exec "$n" cat /etc/resolv.conf
    if docker exec "$n" getent hosts ghcr.io >/dev/null 2>&1; then
      echo "OK getent ghcr.io on $n"
    else
      echo "WARN: getent ghcr.io still failing on $n" >&2
    fi
  done
}

kubeconfig_for_cluster() {
  # cluster: apps|infra|platform
  local cluster="$1"
  local src out cp_name
  src="$ASRAX_HOME/kubeconfig.am-${ENV_NAME}-${cluster}.yaml"
  if [[ ! -f "$src" ]]; then
    if [[ -f "$ASRAX_HOME/kubeconfig.${ENV_NAME}" ]]; then
      echo "$ASRAX_HOME/kubeconfig.${ENV_NAME}"
      return 0
    fi
    return 1
  fi
  cp_name="am-${ENV_NAME}-${cluster}-control-plane"
  if ! docker inspect "$cp_name" >/dev/null 2>&1; then
    return 1
  fi
  out="/tmp/kubeconfig.am-${ENV_NAME}-${cluster}.dns.yaml"
  # Prefer host-published Kind API ports (survive bridge IP churn / hairpin issues).
  # Contabo convention: infra :6443, apps :6444 (see docker port). Fall back to container IP.
  python3 - "$src" "$cp_name" "$out" <<'PY'
import re, socket, subprocess, sys
src, cp_name, dst = sys.argv[1], sys.argv[2], sys.argv[3]
t = open(src).read()
candidates = []
# Prefer container IP (valid Kind TLS SANs). Fall back to host-published ports.
try:
    ip = subprocess.check_output(
        ["docker", "inspect", "-f", "{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}", cp_name],
        text=True,
    ).split()[0]
    for port in (6443, 6444, 6445):
        candidates.append((ip, port))
except Exception:
    pass
try:
    ports = subprocess.check_output(["docker", "port", cp_name], text=True)
    for line in ports.splitlines():
        m = re.search(r"^(\d+)/tcp\s+->\s+[^:]+:(\d+)\s*$", line.strip())
        if m:
            candidates.append(("127.0.0.1", int(m.group(2))))
except Exception:
    pass
for host, port in candidates:
    try:
        s = socket.create_connection((host, port), 2)
        s.close()
        rewritten = re.sub(r"(https?://)[^\s]+", f"https://{host}:{port}", t, count=1)
        if host in ("127.0.0.1", "localhost"):
            # kubectl rejects CA + insecure-skip-tls-verify together
            rewritten = re.sub(r"(?m)^[ \t]*certificate-authority-data:[^\n]*\n", "", rewritten)
            rewritten = re.sub(r"(?m)^[ \t]*certificate-authority:[^\n]*\n", "", rewritten)
            if "insecure-skip-tls-verify" not in rewritten:
                rewritten = rewritten.replace("cluster:\n", "cluster:\n    insecure-skip-tls-verify: true\n", 1)
            else:
                rewritten = re.sub(
                    r"insecure-skip-tls-verify:\s*\w+",
                    "insecure-skip-tls-verify: true",
                    rewritten,
                )
        open(dst, "w").write(rewritten)
        print(f"kubeconfig {cp_name} -> https://{host}:{port}", file=sys.stderr)
        break
    except OSError:
        continue
else:
    raise SystemExit(f"no API for {cp_name}")
PY
  echo "$out"
}

patch_coredns_forward() {
  local cluster="$1"
  local kc
  if ! kc=$(kubeconfig_for_cluster "$cluster"); then
    echo "skip CoreDNS $cluster (no kubeconfig/node)"
    return 0
  fi
  export KUBECONFIG="$kc"
  # Prefer context matching cluster when using merged kubeconfig
  if kubectl config get-contexts -o name 2>/dev/null | grep -qx "${ENV_NAME}-${cluster}"; then
    kubectl config use-context "${ENV_NAME}-${cluster}" >/dev/null
  elif kubectl config get-contexts -o name 2>/dev/null | grep -qx "kind-am-${ENV_NAME}-${cluster}"; then
    kubectl config use-context "kind-am-${ENV_NAME}-${cluster}" >/dev/null
  fi

  echo "--- CoreDNS forward on ${ENV_NAME}-${cluster} (KUBECONFIG=$kc) ---"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' || true
    echo
    return 0
  fi

  DNS1="$DNS1" DNS2="$DNS2" python3 <<'PY'
import json, os, re, subprocess, tempfile, sys

d1, d2 = os.environ["DNS1"], os.environ["DNS2"]
want = f"forward . {d1} {d2}"

def run(cmd, check=True, input=None):
    r = subprocess.run(cmd, check=False, capture_output=True, text=True, input=input)
    if check and r.returncode != 0:
        sys.stderr.write((r.stderr or r.stdout or "") + f"\ncmd failed ({r.returncode}): {cmd}\n")
        raise subprocess.CalledProcessError(r.returncode, cmd, r.stdout, r.stderr)
    return r

r = run(["kubectl", "-n", "kube-system", "get", "configmap", "coredns", "-o", "json"])
doc = json.loads(r.stdout)
core = doc["data"]["Corefile"]

# One-line health { lameduck Ns } crashes CoreDNS — normalize before forward edit.
core = re.sub(
    r"(?m)^([ \t]*)health[ \t]*\{[ \t]*lameduck[ \t]+([^}]+)\}[ \t]*$",
    r"\1health {\n\1   lameduck \2\n\1}",
    core,
)

# Replace any "forward . ..." line (with optional trailing block) carefully:
# Match: forward . SOMETHING { ... }  OR  forward . SOMETHING
pat = re.compile(
    r"(^[ \t]*)forward[ \t]+\.[ \t]+[^\n{]*(?:\{[^{}]*\})?",
    re.MULTILINE,
)

def repl(m):
    indent = m.group(1)
    # Preserve a following brace block if present was only for options; rewrite cleanly.
    return f"{indent}forward . {d1} {d2} {{\n{indent}   max_concurrent 1000\n{indent}}}"

new_core, n = pat.subn(repl, core, count=1)
if n == 0:
    print("ERROR: no forward plugin found in Corefile", file=sys.stderr)
    sys.exit(1)

if new_core == core and want in core:
    print(f"coredns forward already {want}")
    sys.exit(0)

patch = json.dumps({"data": {"Corefile": new_core}})
with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
    f.write(patch)
    path = f.name
try:
    run(["kubectl", "-n", "kube-system", "patch", "configmap", "coredns", "--type", "merge", "--patch-file", path])
finally:
    os.unlink(path)

print(f"patched coredns -> {want}")
run(["kubectl", "-n", "kube-system", "rollout", "restart", "deployment/coredns"], check=False)
run(["kubectl", "-n", "kube-system", "rollout", "status", "deployment/coredns", "--timeout=90s"], check=False)
PY
}

prove_pull() {
  local node="am-${ENV_NAME}-apps-control-plane"
  if ! docker inspect "$node" >/dev/null 2>&1; then
    echo "skip prove: missing $node"
    return 0
  fi
  echo "=== prove DNS/pull on $node ==="
  docker exec "$node" getent hosts ghcr.io || true
  # Public image: DNS success = resolve + pull (or auth/not-found after lookup).
  if docker exec "$node" crictl pull docker.io/library/busybox:1.36 2>&1 | tee /tmp/am-crictl-pull.log; then
    echo "OK crictl pull busybox"
  else
    if grep -qiE 'unauthorized|denied|403|401|manifest unknown|not found' /tmp/am-crictl-pull.log; then
      echo "OK DNS path (registry responded after successful lookup)"
    elif grep -qiE 'lookup|server misbehaving|no such host|i/o timeout' /tmp/am-crictl-pull.log; then
      echo "FAIL still DNS" >&2
      return 1
    else
      echo "WARN crictl pull failed for non-DNS reason; see /tmp/am-crictl-pull.log" >&2
    fi
  fi
}

apply_daemon_json
patch_kind_node_resolv
# CoreDNS on every live cluster on this host
for c in apps infra platform; do
  patch_coredns_forward "$c" || echo "WARN: CoreDNS patch failed for $c"
done
if [[ "$DRY_RUN" -eq 0 ]]; then
  prove_pull || true
fi
echo "== ensure-kind-host-dns done =="
