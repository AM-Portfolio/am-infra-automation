#!/usr/bin/env bash
# Emit JSON: {ip, jwt, ca} for Contabo apps G25 Vault fix. Run on VPS.
set -euo pipefail
export KUBECONFIG=/data/am-state/kubeconfig.am-prod-apps.yaml
IP="$(docker inspect -f '{{(index .NetworkSettings.Networks "kind").IPAddress}}' am-prod-apps-control-plane)"
JWT="$(kubectl -n kube-system create token vault-auth-reviewer --duration=8760h)"
CA="$(kubectl get cm -n kube-system kube-root-ca.crt -o jsonpath='{.data.ca\.crt}')"
python3 -c 'import json,sys; print(json.dumps({"ip":sys.argv[1],"jwt":sys.argv[2],"ca":sys.argv[3]}))' "$IP" "$JWT" "$CA"
