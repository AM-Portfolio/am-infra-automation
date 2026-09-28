#!/usr/bin/env bash
# Fix DR/prod Keycloak scopes using admin password from k8s secret if env file fails.
set -euo pipefail
ENV="${1:-dr}"
KCFG="${KUBECONFIG:-/data/am-state/kubeconfig.am-${ENV}-infra.yaml}"
SCRIPT=/tmp/fix-keycloak-oidc-scopes.py
CREDS="/data/am-state/credentials/${ENV}/keycloak-admin.env"

NODE_PORT="$(kubectl --kubeconfig "$KCFG" -n identity get svc keycloak -o jsonpath='{.spec.ports[?(@.port==8080)].nodePort}')"
NODE_IP="$(kubectl --kubeconfig "$KCFG" get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
KC_URL="http://${NODE_IP}:${NODE_PORT}"
echo "KC_URL=$KC_URL"

PW="$(kubectl --kubeconfig "$KCFG" -n identity get secret keycloak-admin -o jsonpath='{.data.password}' | base64 -d)"
USER="$(kubectl --kubeconfig "$KCFG" -n identity get secret keycloak-admin -o jsonpath='{.data.user}' 2>/dev/null | base64 -d || true)"
USER="${USER:-admin}"
echo "admin_user=$USER pw_len=${#PW}"

# refresh local creds file (keep issuer public)
ISSUER="https://auth.asrax.in/realms/am-realm"
[[ "$ENV" == "dr" ]] && ISSUER="https://auth-dr.asrax.in/realms/am-realm"
AUTH_HOST="${ISSUER#https://}"
AUTH_HOST="${AUTH_HOST%%/*}"
umask 077
cat >"$CREDS" <<EOF
KEYCLOAK_ADMIN_USER=$USER
KEYCLOAK_ADMIN_PASSWORD=$PW
KEYCLOAK_REALM=am-realm
KEYCLOAK_URL=$KC_URL
ISSUER_URL=$ISSUER
FLEET_ENV=$ENV
EOF
ln -sfn "$CREDS" "/data/am-state/credentials/${ENV}-keycloak-admin.env"

python3 "$SCRIPT" --env "$ENV"
# restore public KEYCLOAK_URL for humans
sed -i "s|^KEYCLOAK_URL=.*|KEYCLOAK_URL=https://${AUTH_HOST}|" "$CREDS"
echo "restored KEYCLOAK_URL=https://${AUTH_HOST}"
