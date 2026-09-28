#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:$PATH
export KUBECONFIG=/data/am-state/kubeconfig.am-dr-platform.yaml
chown -R am-ops:am-ops /home/am-ops/src/am-platform 2>/dev/null || true
test -f /home/am-ops/src/am-platform/automation/helm/novu/Chart.yaml
echo "novu chart present"

set -a
# shellcheck disable=SC1091
source /data/am-state/credentials/dr-infra-stores.env
set +a
docker run --rm --network kind mongo:7 \
  mongosh "mongodb://admin:${MONGO_PASSWORD}@mongodb-dr.asrax.in:27017/admin?authSource=admin" --quiet \
  --eval 'db.getSiblingDB("novu").createCollection("_init"); print("novu db ok")'

cd /opt/am-infra-automation/terraform/kind-fleet/dr/platform
nohup terraform apply -auto-approve -input=false \
  -target=module.novu \
  -target=module.route_novu \
  > /tmp/dr-novu-apply.log 2>&1 &
echo "PID=$!"
sleep 15
tail -30 /tmp/dr-novu-apply.log
