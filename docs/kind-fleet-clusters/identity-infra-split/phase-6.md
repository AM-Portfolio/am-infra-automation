# Phase 6 — DR 1 Kind + R2 slave + CF services cutover (TF)

**Goal:** Single Kind on DR via **TF**. R2 **auto-sync** DBs + platform (slave) via **TF-managed** CronJob/Job. Same domains/creds. Cutover = **services** only. See [FAILOVER.md](FAILOVER.md) · [TF-OUTLINE.md](TF-OUTLINE.md).

**Prereq:** Contabo Phases **1–3** green; prefer Phase 5 dump module on. Pointer: [dr/](../dr/) — do not rewrite finished DR history boxes.

## Implement

- [ ] `terraform apply` **one** Kind on DR VPS (NS: stores + platform + apps) — cluster module only *(TF flag ready: `dr/platform` `co_locate_on_infra`; default false — plan before apply)*
- [x] Apply **TF** R2 → DR restore/sync CronJob/Job for DBs + platform (master→slave) — `module.r2_db_pull` CronJob `am-r2-db-pull` `30 */6 * * *` on `am-dr-infra` / `infra` (2026-09-26). Full restore soak deferred (first Job hit backoff mid-`platform` PG; CronJob remains SoT).
- [ ] Confirm **no** public `*-dr` DNS for postgres/mongo/platform/auth
- [ ] Same credentials / OIDC clients as prod
- [ ] Document CF origin swap for **same** hostnames ([FAILOVER.md](FAILOVER.md))
- [ ] GitOps allowlist / sync-wave for P0 services first (Argo Applications — not a hand script)
- [ ] Drill (when approved): CF → DR; start allowlist; scale rest later

### Allowlist (services)

Gateway · Keycloak + am-identity · am-subscription · user APIs · am-market-data · am-modern-ui · asrax-ui minimal

## Test

Use [tests/phase-6.md](tests/phase-6.md).

- [ ] DR single Kind Running (created by TF)
- [x] R2 auto-sync CronJob/Job from TF; last prefix known — `am-r2-db-pull` · SoT `prod/latest/` (stamp from Contabo dump)
- [ ] No public DR store/platform endpoints
- [ ] Drill or dry-run: allowlist order documented
- [ ] Same-domain cutover steps in FAILOVER.md checked

## Grown

- [ ] Contabo remains primary until explicit CF promote
- [ ] DR warm for DBs+platform; services ready for allowlist
- [ ] Nonprod still lean 1 Kind (no DR mandate)

## Stop if fail

Sync broken or CF half-switched → revert origin to Contabo; fix TF sync module first.

## Refuse

- Public `*-dr` DB/platform DNS
- Hydrate-only-on-outage
- Bring-all-apps before P0 green
- Multi-Kind recreate on DR (`am-dr-apps` + `am-dr-platform` as separate creates) for this target
- Preprod full platform on DR
- New surgery scripts instead of TF modules for Kind / dump / sync
