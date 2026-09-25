# Retire sync_keycloak_admin_to_vault.py — Keycloak admin is SoT via:
#   1) kind-fleet/{env}/platform null_resource.write_keycloak_admin_env
#      → /data/am-state/credentials/{env}-keycloak-admin.env
#   2) kind-fleet/{env}/vault-apps module.seed (apps-vault-seed)
#      → apps/data/{env}/services/am-identity KEYCLOAK_ADMIN_*
#
# Re-apply: platform then vault-apps. Do not vault kv patch from shell.
