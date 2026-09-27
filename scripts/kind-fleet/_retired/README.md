# Retired Kind-fleet one-shots

These scripts were live surgery. Do not run them as SoT.

Ownership now:
- Edge / Traefik apps bridge / Vault seed / Keycloak admin → Terraform
- Application desired state → am-gitops PR + Argo sync
- Verify → `phase_gates` (`PYTHONPATH=scripts/kind-fleet python -m phase_gates --env <env> --wave …`)
- Debug → parent `scripts/kind-fleet` (`_debug_*`, `_vault_*` read) — never new `dr-phase*` / `tmp-*` / `_fix_*`

**`dr-phase5-surgery/`** — disposable VPS SSH wrappers from DR Phase 5c–5e. Lessons already landed in gitops overlays / TF; re-run = digression. Same rule as prod: *Do not add disposable probes — extend `phase_gates`.*

See `../README.md`.
