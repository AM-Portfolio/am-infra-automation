# Apps Vault seed (Kind fleet)
#
# Seeds `apps/data/<env>/infra/*` and `apps/data/<env>/services/*` so Argo-synced
# pods can mount CSI secrets. Lives in am-infra-automation only (not am-gitops).
#
# Module: terraform/modules/core/apps-vault-seed
# Catalog: terraform/modules/core/apps-vault-seed/catalog/services.yaml
# Dev stack: terraform/kind-fleet/dev/vault-apps
#
# Apply (dev):
#   cd terraform/kind-fleet
#   .\init-backend.ps1 -Env dev -Role vault-apps
#   terraform -chdir=dev/vault-apps init -backend-config=backend.hcl
#   terraform -chdir=dev/vault-apps apply
#
# Store creds: ~/.asrax/credentials.d/dev-infra-stores.env
# Vault token: ~/.asrax/vault-dev-infra.json
# Placeholders (`<env>-fleet-…`) are intentional; replace real third-party secrets in Vault when ready.
