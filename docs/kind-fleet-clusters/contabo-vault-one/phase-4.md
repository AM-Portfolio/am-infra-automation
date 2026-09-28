# Phase 4 — Lean preprod prove (apps + agents)

**Status: BLOCKED until Phase 3 Grown.**

**Goal:** Prove lean preprod **apps** + **agents** fleets on the one Contabo nonprod Kind; gap-fill missing in-scope secrets via TF only; confirm laptop dig unchanged and **prod Kind untouched**.

## Implement (do not start until Phase 3 Grown)

- [ ] Diff Running vs CrashLoop CSI for `am-apps-preprod` and `am-agents-preprod`
- [ ] Contabo Argo: all enrolled preprod apps + agents still Synced/Healthy
- [ ] TF gap-fill only for remaining app/store/agent secret paths (no kafka/n8n/platform)
- [ ] Confirm laptop dig (`am-dev-apps`) still green — **not** Contabo dig NS
- [ ] Confirm Contabo **prod** Kind unchanged
- [ ] Spot-check Google login on Contabo preprod UI
- [ ] Spot-check at least one agent path (e.g. ai-gateway / mcp) on preprod
- [ ] Key-name parity vs Contabo prod for **app/agent** paths only (document intentional kafka/n8n gaps)
- [ ] Confirm nonprod NS set is still only keepers: `am-apps-preprod`, `am-agents-preprod`, edge

## Test

Use [tests/phase-4.md](tests/phase-4.md) when unblocked.

## Grown

- [ ] Lean preprod apps + agents stable
- [ ] Google login + agent smoke green
- [ ] Laptop dig unchanged; prod Kind untouched
- [ ] Ready for Phase 5 retire (vault-preprod / Kafka / n8n / platform / extra NS)

## Stop if fail

Missing secrets for required apps/agents → fix via TF; do not delete vault-preprod yet.

## Refuse

- Execute before Phase 3 Grown
- Re-adding Kafka/n8n/platform to preprod
- Surgery scripts as SoT
- Mutating Contabo prod Kind or `apps/data/prod`
- Touching laptop dig Kind for “fixes”
