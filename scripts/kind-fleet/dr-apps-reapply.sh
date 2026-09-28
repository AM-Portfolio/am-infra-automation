#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:$PATH
python3 <<'PY'
from pathlib import Path
for p in [
    Path("/data/am-state/kubeconfig.am-dr-apps.yaml"),
    Path("/home/am-ops/.asrax/kubeconfig.am-dr-apps.yaml"),
]:
    if not p.exists():
        print("missing", p)
        continue
    t = p.read_text()
    t2 = (
        t.replace("https://127.0.0.1:6444", "https://129.121.128.131:6444")
        .replace("https://0.0.0.0:6444", "https://129.121.128.131:6444")
    )
    p.write_text(t2)
    print("rewrote", p)
    for line in t2.splitlines():
        if "server:" in line:
            print(" ", line.strip())
PY
chown am-ops:am-ops /home/am-ops/.asrax/kubeconfig.am-dr-apps.yaml 2>/dev/null || true
chmod 600 /data/am-state/kubeconfig.am-dr-apps.yaml /home/am-ops/.asrax/kubeconfig.am-dr-apps.yaml 2>/dev/null || true
iptables -t nat -C PREROUTING -p tcp --dport 6444 -j DNAT --to-destination 127.0.0.1:6444 2>/dev/null || \
  iptables -t nat -A PREROUTING -p tcp --dport 6444 -j DNAT --to-destination 127.0.0.1:6444
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-apps.yaml
kubectl get --raw=/version | head -c 120; echo
# kill prior apply if still running
pkill -f 'terraform apply.*dr/apps' 2>/dev/null || true
sleep 2
cd /opt/am-infra-automation/terraform/kind-fleet/dr/apps
nohup terraform apply -auto-approve -input=false > /tmp/dr-apps-apply.log 2>&1 &
echo APPS_TF_PID=$!
sleep 5
tail -20 /tmp/dr-apps-apply.log | sed 's/\x1b\[[0-9;]*m//g'
