# Phase 5 — Retire vault-preprod / Kafka / n8n / platform (nonprod only)

**Status: BLOCKED until Phase 4 Grown** (+ backup evidence).

**Goal:** On Contabo **nonprod** only: remove vault-preprod, Kafka, n8n, platform stacks, and any NS beyond the three keepers. Contabo **prod** Kind stays full. Laptop dig unchanged.

**Keep after retire:** `am-apps-preprod`, `am-agents-preprod`, edge (`traefik` + `cloudflared`).

## Implement (do not start yet)

- [ ] Confirm no Application / CSI still addresses `vault-preprod.asrax.in`
- [ ] Confirm Contabo dig NS already gone (Phase 3f) or finish drain with user confirm
- [ ] TF/gitops remove vault-preprod Helm/STS + injector (nonprod only)
- [ ] Remove Kafka, n8n, platform Argo apps/workloads per [INVENTORY.md](INVENTORY.md) remove-candidates
- [ ] Drop DNS/tunnel dependency on `vault-preprod.asrax.in` when unused
- [ ] Wipe leftover NS beyond the three keepers — **inventory → user confirm → double-check → delete**
- [ ] Record evidence; update INVENTORY
- [ ] Spot-check: lean apps + agents still Ready on Contabo Vault CSI; prod Kind untouched

## Test

Use [tests/phase-5.md](tests/phase-5.md) when unblocked.

## Grown

- [ ] Contabo Vault serves prod + lean preprod + dig (`apps/data/dev` for laptop)
- [ ] Contabo nonprod Kind = **only** `am-apps-preprod` + `am-agents-preprod` + edge — no vault-preprod / Kafka / n8n / platform / Contabo dig
- [ ] Contabo **prod** Kind untouched
- [ ] Laptop dig still green

## Stop if fail

Anything still depending on vault-preprod / kafka / n8n → do not delete; roll back.

## Refuse

- Execute before Phase 4 green
- Delete without backup evidence + user confirm
- Surgery scripts as SoT
- Touching Contabo `apps/data/prod` or Contabo **prod** Kind
- Breaking lean preprod apps/agents fleets
- Deleting laptop dig Kind
