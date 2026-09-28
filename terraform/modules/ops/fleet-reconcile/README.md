# fleet-reconcile — apply fleet-gaps actions via `am gitops` (no kubectl sync).
#
# - action=pin  → promote workflow (GitHub / CODEOWNERS)
# - action=sync → Argo refresh+sync, ordered by catalog/sync-order.yaml
#
# Default dry_run=true. Mutations run **once** through:
#   am gitops reconcile --gaps-file … --apply
# (never parallel for_each sync — Kind RAM/CPU).
#
# Prefer agent path: `am gitops reconcile --env prod` (same gap schema).
