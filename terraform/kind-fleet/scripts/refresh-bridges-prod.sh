#!/usr/bin/env bash
# Contabo host wrapper: Kind API via Docker network IP (cert SAN), not 127.0.0.1.
set -euo pipefail
CP_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-prod-infra-control-plane | head -1 | tr -d '[:space:]')"
if [[ -z "$CP_IP" ]]; then
  echo "am-prod-infra-control-plane not found" >&2
  exit 1
fi
kind get kubeconfig --name am-prod-infra | sed "s|https://0.0.0.0:6443|https://${CP_IP}:6443|" > /run/am-kc-prod-infra.yaml
export INFRA_KUBECONFIG=/run/am-kc-prod-infra.yaml
export ENV=prod
exec /opt/am/am-infra-automation/terraform/kind-fleet/scripts/refresh-cross-cluster-bridges.sh prod
