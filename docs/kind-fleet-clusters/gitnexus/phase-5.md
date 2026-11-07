# GitNexus — Phase 5 (Consumers + Grown)

Tests: [tests/phase-5.md](tests/phase-5.md).

## Prereq

Phase 3 green. Phase 4 optional.

## Implement

- [x] qa-agent / helm: `GNX_MCP_URL=https://gitnexus.asrax.in` in values.dev + values.preprod.
- [x] TEAM-MCP docs cite public URL (`am-gitnexus`).
- [x] `am-scripts/code-intelligence/README.md` stub → `am-gitnexus` + this track.
- [x] Fill [TEST_REPORT.md](TEST_REPORT.md) UC rows + phase status.
- [ ] Optional: index additional `am-portfolio` group repos as capacity allows.

## Test

See [tests/phase-5.md](tests/phase-5.md).

## Grown

- [ ] Track docs remain SoT under `kind-fleet-clusters/gitnexus/`.
- [ ] Hub SoT is `am-gitnexus` only.
- [ ] Scale apps/agents back to 1 when product work resumes (out of band).

## Refuse

- Re-homing hub under `am-scripts`.
- qa-agent owning `gitnexus analyze` (ADR-QA-001).
