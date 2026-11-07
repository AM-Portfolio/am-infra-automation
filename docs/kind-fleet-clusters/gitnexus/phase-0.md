# GitNexus — Phase 0 (Inventory + confirm)

Tests: [tests/phase-0.md](tests/phase-0.md).

## Prereq

Operator access to Contabo nonprod kubeconfig / SSH. No scale or wipe yet.

## Implement

- [x] `curl` `https://gitnexus.asrax.in/health` — **530** (2026-09-28 laptop).
- [x] Cloudflare: DNS exists; prior research — hostname missing from prod tunnel ingress; target **nonprod** tunnel for cutover.
- [ ] `kubectl` (prod + nonprod): leftover `deploy/gitnexus` — **blocked** (API timeout to Contabo / nonprod).
- [ ] Inventory hostPath leftovers on node — **blocked** (needs SSH).
- [x] NS to reclaim documented: `am-apps-dev`, `am-agents-dev`, `am-apps-preprod`, `am-agents-preprod` (confirm live cluster per NONPROD_DUAL).
- [ ] Record free `MemAvailable` on nonprod node — **blocked**.
- [ ] **User confirm** scale-to-0 targets before Phase 1 (on-box).

## Test

See [tests/phase-0.md](tests/phase-0.md). Laptop gates for public health recorded in [TEST_REPORT.md](TEST_REPORT.md).

## Grown

- [x] Inventory notes in [TEST_REPORT.md](TEST_REPORT.md) Phase 0 row.
- [x] No destructive actions taken in this phase.

## Refuse

- Scale or delete without user confirm.
- Any `kubectl delete` on nonprod for reclaim (scale only).
- Point DNS cutover before Phase 2 serve is healthy locally.
