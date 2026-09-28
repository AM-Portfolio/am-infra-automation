#!/usr/bin/env bash
# Save / migrate AM fleet credentials under /data/am-state/credentials/<env>/
# and refresh Vault apps/data/<env>/oidc + host oidc.env / sso-test-users.env.
#
# Usage (on the VPS that owns the env):
#   sudo bash scripts/kind-fleet/save-env-credentials.sh --env prod
#   sudo bash scripts/kind-fleet/save-env-credentials.sh --env dr
#   bash scripts/kind-fleet/save-env-credentials.sh --env dev   # laptop/VPS2
#
# Never prints secret values. Never commits.
set -euo pipefail

ENV=""
CREDS_ROOT="${CREDS_ROOT:-/data/am-state/credentials}"
DOMAIN="${DOMAIN:-asrax.in}"

usage() {
  echo "Usage: $0 --env prod|dr|dev" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ "$ENV" == "prod" || "$ENV" == "dr" || "$ENV" == "dev" ]] || usage

case "$ENV" in
  prod)
    VAULT_ADDR_DEFAULT="https://vault.${DOMAIN}"
    VAULT_KEYS_DEFAULT="/data/am-state/vault-prod-infra.json"
    AUTH_HOST_DEFAULT="auth.${DOMAIN}"
    ISSUER_DEFAULT="https://${AUTH_HOST_DEFAULT}/realms/am-realm"
    ARGO_HOST_DEFAULT="argocd.${DOMAIN}"
    ;;
  dr)
    VAULT_ADDR_DEFAULT="https://vault-dr.${DOMAIN}"
    VAULT_KEYS_DEFAULT="/data/am-state/vault-dr-infra.json"
    AUTH_HOST_DEFAULT="auth-dr.${DOMAIN}"
    ISSUER_DEFAULT="https://${AUTH_HOST_DEFAULT}/realms/am-realm"
    ARGO_HOST_DEFAULT="argocd-dr.${DOMAIN}"
    ;;
  dev)
    CREDS_ROOT="${CREDS_ROOT:-${HOME}/.asrax/credentials.d}"
    VAULT_ADDR_DEFAULT="https://vault-dev.${DOMAIN}"
    VAULT_KEYS_DEFAULT="${HOME}/.asrax/vault-dev-infra.json"
    AUTH_HOST_DEFAULT="auth-dev.${DOMAIN}"
    ISSUER_DEFAULT="https://${AUTH_HOST_DEFAULT}/realms/am-realm"
    ARGO_HOST_DEFAULT="argocd-dev.${DOMAIN}"
    ;;
esac

VAULT_ADDR="${VAULT_ADDR:-$VAULT_ADDR_DEFAULT}"
VAULT_KEYS="${VAULT_KEYS:-$VAULT_KEYS_DEFAULT}"
AUTH_HOST="${AUTH_HOST:-$AUTH_HOST_DEFAULT}"
ISSUER_URL="${ISSUER_URL:-$ISSUER_DEFAULT}"
ARGO_HOST="${ARGO_HOST:-$ARGO_HOST_DEFAULT}"

if [[ "$ENV" == "dev" ]]; then
  DIR="${CREDS_ROOT}"
  # Prefer nested when using /data/am-state
  if [[ "$CREDS_ROOT" == /data/am-state/credentials ]]; then
    DIR="${CREDS_ROOT}/${ENV}"
  else
    DIR="${CREDS_ROOT}/dev"
    mkdir -p "$DIR" 2>/dev/null || DIR="${HOME}/.asrax/credentials.d"
  fi
else
  DIR="${CREDS_ROOT}/${ENV}"
fi

mkdir -p "$DIR" "$CREDS_ROOT"
chmod 700 "$DIR" 2>/dev/null || true
umask 077

log() { echo "[save-env-credentials] $*"; }

# --- migrate flat files into nested layout + compat symlinks ---
migrate_flat() {
  local flat="$1" nested="$2"
  if [[ -f "$flat" && ! -L "$flat" ]]; then
    if [[ ! -f "$nested" ]]; then
      log "migrate $(basename "$flat") -> ${ENV}/$(basename "$nested")"
      mv "$flat" "$nested"
    else
      log "keep nested $(basename "$nested"); archive flat $(basename "$flat")"
      mv "$flat" "${flat}.pre-nested.bak"
    fi
  fi
  if [[ -f "$nested" ]]; then
    ln -sfn "$nested" "$flat"
    log "compat symlink $(basename "$flat") -> ${ENV}/$(basename "$nested")"
  fi
}

if [[ "$ENV" == "prod" || "$ENV" == "dr" ]]; then
  migrate_flat "${CREDS_ROOT}/${ENV}-keycloak-admin.env" "${DIR}/keycloak-admin.env"
  migrate_flat "${CREDS_ROOT}/${ENV}-infra-stores.env" "${DIR}/infra-stores.env"
fi

# --- vault-root.env from host unseal/keys file (mode 600) ---
write_vault_root() {
  local out="${DIR}/vault-root.env"
  if [[ ! -f "$VAULT_KEYS" ]]; then
    log "skip vault-root.env (missing $VAULT_KEYS)"
    return 0
  fi
  python3 - <<PY
import json, os
keys_path = os.environ["VAULT_KEYS"]
out = os.environ["OUT"]
addr = os.environ["VAULT_ADDR"]
env = os.environ["FLEET_ENV"]
with open(keys_path, encoding="utf-8-sig") as f:
    data = json.load(f)
token = data.get("root_token") or data.get("token") or ""
unseal = data.get("unseal_keys") or data.get("keys") or []
lines = [
    f"# Vault ops for {env}. Not for git.",
    f"VAULT_ADDR={addr}",
    f"VAULT_KEYS_FILE={keys_path}",
]
if token:
    lines.append(f"VAULT_TOKEN={token}")
if isinstance(unseal, list):
    for i, k in enumerate(unseal):
        lines.append(f"VAULT_UNSEAL_KEY_{i}={k}")
elif isinstance(unseal, str) and unseal:
    lines.append(f"VAULT_UNSEAL_KEY_0={unseal}")
with open(out, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
os.chmod(out, 0o600)
print(f"wrote {out}")
PY
}
export VAULT_ADDR VAULT_KEYS FLEET_ENV="$ENV"
export OUT="${DIR}/vault-root.env"
write_vault_root

# --- enrich keycloak-admin.env with URL fields if present ---
enrich_keycloak() {
  local f="${DIR}/keycloak-admin.env"
  [[ -f "$f" ]] || { log "skip keycloak enrich (no file yet)"; return 0; }
  grep -q '^KEYCLOAK_URL=' "$f" 2>/dev/null || echo "KEYCLOAK_URL=https://${AUTH_HOST}" >>"$f"
  grep -q '^ISSUER_URL=' "$f" 2>/dev/null || echo "ISSUER_URL=${ISSUER_URL}" >>"$f"
  grep -q '^FLEET_ENV=' "$f" 2>/dev/null || echo "FLEET_ENV=${ENV}" >>"$f"
  chmod 600 "$f" || true
  log "enriched keycloak-admin.env"
}
enrich_keycloak

# --- dump OIDC + test users from Vault into host files ---
dump_from_vault() {
  if [[ ! -f "$VAULT_KEYS" ]]; then
    log "skip Vault dump (missing keys file)"
    return 0
  fi
  export VAULT_ADDR ISSUER_URL
  export OIDC_OUT="${DIR}/oidc.env"
  export SSO_OUT="${DIR}/sso-test-users.env"
  python3 - <<'PY'
import json, os, urllib.request, urllib.error

addr = os.environ["VAULT_ADDR"].rstrip("/")
env = os.environ["FLEET_ENV"]
issuer = os.environ["ISSUER_URL"]
oidc_out = os.environ["OIDC_OUT"]
sso_out = os.environ["SSO_OUT"]
keys_path = os.environ["VAULT_KEYS"]

with open(keys_path, encoding="utf-8-sig") as f:
    token = json.load(f).get("root_token") or ""
if not token:
    print("skip_vault_no_token")
    raise SystemExit(0)

def vault(method, path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        f"{addr}/v1/{path}",
        data=data,
        method=method,
        headers={"X-Vault-Token": token, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        if e.code in (404, 403):
            return None
        raise

# List OIDC clients
listed = vault("LIST", f"apps/metadata/{env}/oidc")
keys = []
if listed and isinstance(listed.get("data"), dict):
    keys = list(listed["data"].get("keys") or [])

lines = [f"# OIDC clients for {env}. Not for git.", f"ISSUER_URL={issuer}"]
count = 0
for name in keys:
    name = name.rstrip("/")
    if not name:
        continue
    read = vault("GET", f"apps/data/{env}/oidc/{name}")
    if not read:
        continue
    data = (read.get("data") or {}).get("data") or {}
    secret = data.get("client_secret") or ""
    cid = data.get("client_id") or name
    if secret:
        # ensure issuer_url present in Vault
        vault("POST", f"apps/data/{env}/oidc/{name}", {
            "data": {
                "client_id": cid,
                "client_secret": secret,
                "issuer_url": data.get("issuer_url") or issuer,
            }
        })
    safe = name.upper().replace("-", "_").replace(".", "_")
    lines.append(f"OIDC_{safe}_CLIENT_ID={cid}")
    if secret:
        lines.append(f"OIDC_{safe}_CLIENT_SECRET={secret}")
        count += 1

with open(oidc_out, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
os.chmod(oidc_out, 0o600)
print(f"wrote {oidc_out} clients={count}")

# Test users
users = vault("GET", f"apps/data/{env}/infra/keycloak-test-users")
sso_lines = [f"# SSO test users for {env}. Not for git."]
if users:
    data = (users.get("data") or {}).get("data") or {}
    for k in ("AM_ADMIN_TEST_USERNAME", "AM_ADMIN_TEST_PASSWORD",
              "AM_USER_TEST_USERNAME", "AM_USER_TEST_PASSWORD",
              "am-admin-test", "am-user-test",
              "admin_username", "admin_password", "user_username", "user_password"):
        if k in data and data[k] is not None:
            sso_lines.append(f"{k}={data[k]}")
    if "am-admin-test" in data and "AM_ADMIN_TEST_USERNAME" not in data:
        sso_lines.append("AM_ADMIN_TEST_USERNAME=am-admin-test")
        sso_lines.append(f"AM_ADMIN_TEST_PASSWORD={data['am-admin-test']}")
    if "am-user-test" in data and "AM_USER_TEST_USERNAME" not in data:
        sso_lines.append("AM_USER_TEST_USERNAME=am-user-test")
        sso_lines.append(f"AM_USER_TEST_PASSWORD={data['am-user-test']}")
    with open(sso_out, "w", encoding="utf-8") as f:
        f.write("\n".join(sso_lines) + "\n")
    os.chmod(sso_out, 0o600)
    print(f"wrote {sso_out}")
else:
    print(f"skip sso-test-users (no vault path apps/data/{env}/infra/keycloak-test-users)")
PY
}
dump_from_vault
# Prefer TF-state extract when platform state exists (fills oidc/sso/argo even if Vault token lacks apps ACL).
TF_STATE="${TF_STATE:-/data/am-state/terraform/${ENV}/platform/terraform.tfstate}"
EXTRACT_PY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_extract_tf_creds.py"
if [[ -f "$TF_STATE" ]]; then
  if [[ -f "$EXTRACT_PY" ]]; then
    log "extract from TF state via $EXTRACT_PY"
    python3 "$EXTRACT_PY" "$ENV" || log "TF extract warn"
  elif [[ -f /tmp/_extract_tf_creds.py ]]; then
    log "extract from TF state via /tmp/_extract_tf_creds.py"
    python3 /tmp/_extract_tf_creds.py "$ENV" || log "TF extract warn"
  fi
fi

# --- optional Argo admin from k8s secret ---
write_argocd_from_k8s() {
  local out="${DIR}/argocd-admin.env"
  local kc="${KUBECONFIG:-/data/am-state/kubeconfig.am-${ENV}-infra.yaml}"
  if [[ "$ENV" == "dev" ]]; then
    kc="${KUBECONFIG:-${HOME}/.asrax/kubeconfig.am-dev-infra.yaml}"
  fi
  if ! command -v kubectl >/dev/null 2>&1; then
    log "skip argocd-admin (no kubectl)"
    return 0
  fi
  if [[ ! -f "$kc" ]]; then
    log "skip argocd-admin (no kubeconfig $kc)"
    return 0
  fi
  local pass
  pass="$(KUBECONFIG="$kc" kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' 2>/dev/null || true)"
  if [[ -z "$pass" ]]; then
    log "skip argocd-admin (secret missing)"
    return 0
  fi
  pass="$(printf '%s' "$pass" | base64 -d 2>/dev/null || true)"
  [[ -n "$pass" ]] || return 0
  cat >"$out" <<EOF
ARGOCD_ADMIN_USER=admin
ARGOCD_ADMIN_PASSWORD=$pass
ARGOCD_HOST=https://${ARGO_HOST}
FLEET_ENV=${ENV}
EOF
  chmod 600 "$out"
  log "wrote argocd-admin.env"
}
write_argocd_from_k8s

# --- README (no secrets) ---
cat >"${DIR}/README.txt" <<EOF
AM fleet credentials for env=${ENV} (host SoT).
Files: keycloak-admin.env, infra-stores.env, oidc.env, sso-test-users.env, argocd-admin.env, vault-root.env
Compat symlinks (prod/dr): ${CREDS_ROOT}/${ENV}-keycloak-admin.env, ${ENV}-infra-stores.env
Vault mirror: apps/data/${ENV}/oidc/* and apps/data/${ENV}/infra/keycloak-test-users
Never commit. Mode 600/700. Refresh: scripts/kind-fleet/save-env-credentials.sh --env ${ENV}
EOF
chmod 644 "${DIR}/README.txt" || true

log "done env=${ENV} dir=${DIR}"
log "listing (names only):"
ls -la "$DIR" | awk '{print $1, $NF}'
if [[ "$ENV" == "prod" || "$ENV" == "dr" ]]; then
  ls -la "${CREDS_ROOT}/${ENV}-keycloak-admin.env" "${CREDS_ROOT}/${ENV}-infra-stores.env" 2>/dev/null \
    | awk '{print $1, $NF}' || true
fi
