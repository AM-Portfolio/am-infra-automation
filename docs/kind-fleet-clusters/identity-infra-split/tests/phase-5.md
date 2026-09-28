# Phase 5 tests — harden + R2 dump (TF)

**Phase:** [../phase-5.md](../phase-5.md)

## Test

- [ ] Quotas / headroom checks
- [x] Continuous dump CronJob/Job from **TF** (not a surgery script)
- [x] Labels `prod/` vs `preprod/`
- [x] TF→host→Kind matrix (2 / 1 / 1) — Contabo live 2 Kind

## Grown

- [x] Phases 1–3 still green after harden

## Evidence

Matrix + TF resource/CronJob name + R2 prefix (no secrets).  
`am-r2-db-dump` · `0 */6 * * *` · R2 `asrax-disaster` → `prod/<stamp>/` + `prod/latest/` (PG platform/subscription/user_platform/lago + mongo + redis). 2026-09-26.
