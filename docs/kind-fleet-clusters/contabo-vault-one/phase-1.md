# Phase 1 — Dev remap + TF outline lock

**Goal:** Lock [PATH_REMAP.md](PATH_REMAP.md) and [TF-OUTLINE.md](TF-OUTLINE.md) for Contabo `apps/data/dev` only. Prefer preprod Google/OIDC. **No** `terraform apply` yet.

**Prereq:** [phase-0.md](phase-0.md) recent preprod dump present (Contabo prod dump may still be blocked).

## Implement

- [x] Build action matrix: recent preprod dump × Contabo dig target × [VAULT_SCHEMA.md](../../../../VPS/vault/VAULT_SCHEMA.md) — see [PATH_REMAP.md](PATH_REMAP.md)
- [x] Mark each leaf: copy-to-dev / skip / remap-value (Contabo live prod dump blocked — July for sparse prod shape)
- [x] Lock Contabo nonprod hosts / `am_*_dev` / `am-dev-realm` (or live Contabo **dev** realm)
- [x] Lock Google/OIDC: prefer **preprod** backup; redirect URIs for Contabo **dev** UI if needed
- [x] Confirm TF root for Contabo (see TF-OUTLINE) — provider `vault.asrax.in`, `env=dev`, separate state
- [x] Confirm plan would **never** write `apps/data/prod`
- [x] Stub only: preprod lean SKIP list (kafka/n8n/platform) — do not execute

## Test

Use [tests/phase-1.md](tests/phase-1.md).

- [x] PATH_REMAP action matrix filled for **dev**
- [x] TF-OUTLINE apply order + state path documented
- [x] Google preference called out for identity/keycloak/gateway paths
- [x] No terraform apply evidence in this phase

## Grown

- [x] Remap + TF outline locked from preprod recent dump
- [ ] Contabo Vault must be healthy before Phase 2 apply (CF 530 as of 2026-09-27)
- [x] Preprod Kind still untouched

## Stop if fail

TF root unclear, Contabo Vault down, or plan would touch prod paths → do not apply.

## Refuse

- No `terraform apply` in this phase
- No preprod overlay / Vault changes
- No surgery scripts as SoT
