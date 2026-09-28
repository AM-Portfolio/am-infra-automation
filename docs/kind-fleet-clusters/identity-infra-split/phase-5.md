# Phase 5 — Harden + continuous R2 dump (TF)

**Goal:** Quotas, headroom, TF matrix, and **Terraform-managed** continuous prod → R2 dump for DR slave (critical DBs).

**Prereq:** [phase-4.md](phase-4.md) done or Contabo-only noted. Prefer Phases 1–3 green. See [TF-OUTLINE.md](TF-OUTLINE.md).

**Unlocked 2026-09-26:** Contabo Phases 1–3 green; Phase 4 Contabo-only note recorded (preprod gone; VPS2 Kind deferred).

## Implement

- [ ] ResourceQuotas / LimitRanges on Contabo infra + apps (**via TF** where modules exist)
- [ ] Disk / RAM alerts per [SIZING.md](SIZING.md)
- [x] Dump labels: `prod/` vs `preprod/` (never mix restore targets) — live prefix `prod/<stamp>/` + `prod/latest/`
- [x] Add/extend **TF module** for continuous dump CronJob/Job: Contabo critical DBs → R2 `asrax-disaster`
  - Minimum: Keycloak/`platform`, user, subscription, market-related as needed for [FAILOVER.md](FAILOVER.md) allowlist
  - Apply via `terraform apply` on the owning root — **not** a laptop surgery script
  - Live 2026-09-26: `module.r2_db_dump` CronJob `am-r2-db-dump` `0 */6 * * *` on `am-prod-infra` / `infra` NS; image `am-r2-db-dump:local` (Kind-loaded)
- [x] Runbook matrix: TF root → host → Kind → NS — [RUNBOOK-MATRIX.md](RUNBOOK-MATRIX.md) (Contabo **2** live; DR target **1**)
- [ ] Vault policy: prod paths not writable from nonprod roles
- [ ] Isolation re-check: nonprod ≠ Contabo stores

## Test

Use [tests/phase-5.md](tests/phase-5.md).

- [ ] Quotas present on critical NS
- [x] Dump CronJob/Job exists from TF (name + schedule documented)
- [x] R2 prefix listable for today’s/`latest` hydrate SoT — `prod/latest/{postgres,mongodb,redis,BACKUP_OK,MANIFEST}`
- [x] TF→host matrix matches live Kind counts — Contabo 2 Kind

## Grown

- [x] Operator can answer “which TF on which host?” — [RUNBOOK-MATRIX.md](RUNBOOK-MATRIX.md)
- [x] Continuous dump ready for Phase 6 DR auto-sync module *(prod dump SoT live)*

## Stop if fail

Quota/deny breaks prod → roll back TF apply; keep IdP/stores up.

## Refuse

- DR CF cutover in this phase
- Dump-only-on-outage design
- Ad-hoc `*.ps1` / `*.sh` dump as SoT
- Deleting Vault to “simplify”
