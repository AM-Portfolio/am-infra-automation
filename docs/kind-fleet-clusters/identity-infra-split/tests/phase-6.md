# Phase 6 tests — DR slave + CF services (TF)

**Phase:** [../phase-6.md](../phase-6.md) · [../FAILOVER.md](../FAILOVER.md) · [../TF-OUTLINE.md](../TF-OUTLINE.md)

## Test

- [ ] DR **one** Kind Running (TF cluster module)
- [x] R2 auto-sync CronJob/Job from TF; last prefix known
- [ ] No public `*-dr` DB/platform DNS
- [ ] Allowlist order matches FAILOVER.md
- [ ] Same-domain CF cutover steps reviewed

## Grown

- [ ] Contabo still primary until promote
- [ ] DBs+platform warm; services cutover-ready

## Evidence

Kind name + TF sync job name + last R2 prefix + CF dry-run notes.  
`am-r2-db-pull` · `30 */6 * * *` · R2 `asrax-disaster` ← `prod/latest/` (leveled 2026-09-26; full restore soak deferred). DR colocate: `co_locate_on_infra` in `dr/platform` (default false).
