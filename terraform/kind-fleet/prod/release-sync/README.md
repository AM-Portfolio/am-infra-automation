# release-sync — Contabo prod consumer of fleet-gaps + fleet-reconcile
#
# Observe Release Glance metrics → classify gaps → optional promote/sync.
#
# ```bash
# cd terraform/kind-fleet/prod/release-sync
# terraform init
# terraform plan                    # dry_run=true (default)
# # mutations (needs am on PATH + AM_ARGOCD_MCP_WRITE=1 + gh auth):
# terraform apply -var='dry_run=false' -var='enable_mutations=true'
# ```
#
# Agents: prefer `am gitops reconcile --env prod` (same schema, no TF required).
