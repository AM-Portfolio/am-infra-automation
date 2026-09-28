# Contabo Vault one — Dev seed + lean preprod (one Kind)

Light track beside [`identity-infra-split/`](../identity-infra-split/). Dig Vault seed (Phases 0–2) targets Contabo Vault; **Phases 3–5** collapse Contabo **nonprod** to **one Kind / three namespaces** and retire Contabo dig NS + vault-preprod clutter. **Prod Kind is never touched.**

Related: [DEV_ON_CONTABO.md](../../../am-gitops/docs/DEV_ON_CONTABO.md) (laptop dig) · [DEV_VAULT_DB_PILOT.md](../../../am-gitops/docs/DEV_VAULT_DB_PILOT.md) · [VAULT_SCHEMA.md](../../../../VPS/vault/VAULT_SCHEMA.md) · TF: [TF-OUTLINE.md](TF-OUTLINE.md) · Inventory: [INVENTORY.md](INVENTORY.md) · Remap: [PATH_REMAP.md](PATH_REMAP.md)

## Recommendation (locked)

**One Contabo Vault** (`https://vault.asrax.in`) holds `apps/data/{dev,preprod,prod}/…`.

**One Contabo nonprod Kind** (`am-vps-nonprod`) — **exactly three namespaces:**

| Namespace | Role |
|-----------|------|
| `am-apps-preprod` | Lean preprod apps |
| `am-agents-preprod` | Lean preprod agents |
| edge (`traefik` + `cloudflared`) | Minimal Traefik + Cloudflare tunnel only |

**CSI (preprod):** JWT `auth/jwt-nonprod` → `apps/data/preprod/*` on `vault.asrax.in` (mirror dig overlay pattern — [overlays/dev/vault-https-contabo.yaml](../../../../am-gitops/overlays/dev/vault-https-contabo.yaml)).

**Stores:** Contabo prod FQDNs (`mongo` / `redis` / `postgres` / `kafka.asrax.in`) — no preprod-local stores plane.

**Contabo dig NS retired** (`am-apps-dev` / `am-agents-dev` on Contabo). Laptop dig (`am-dev-apps` + local Argo) is **out of this track** — see DEV_ON_CONTABO.md.

**Prod Kind / prod AppSets / `apps/data/prod`:** **do not touch.**

**Terraform-first** for Vault seed where TF owns paths; preprod KV already restored 2026-09-28 (see INVENTORY) — do not re-dump for Phase 3a.

## Locked decisions

| Item | Value |
|------|--------|
| Target Vault | Contabo `https://vault.asrax.in` |
| Dev paths (laptop dig) | `apps/data/dev/*` |
| Preprod paths | `apps/data/preprod/*` (38 leaves restored 2026-09-28) |
| Preprod CSI | Overlay → `vault.asrax.in` + JWT (replace [overlays/preprod/vault-https-preprod.yaml](../../../../am-gitops/overlays/preprod/vault-https-preprod.yaml)) |
| Dig CSI (laptop) | [overlays/dev/vault-https-contabo.yaml](../../../../am-gitops/overlays/dev/vault-https-contabo.yaml) |
| Nonprod Kind | **One** — `am-vps-nonprod` |
| Nonprod NS keep | `am-apps-preprod`, `am-agents-preprod`, edge only |
| Contabo dig NS | **Retire** in Phase 3e |
| Laptop dig | Unchanged by Phases 3–5 |
| Preprod lean | No Kafka / n8n / platform stacks on nonprod |
| Never | Overwrite `apps/data/prod`; mutate Contabo **prod** Kind |

```text
Phases 0–2: seed apps/data/dev + laptop dig (local Argo)
  → Phase 3: inventory nonprod → CSI preprod→vault.asrax.in → AppSets
       → edge minimal → drain Contabo dig NS
  → Phase 4: prove lean apps + agents + Google login
  → Phase 5: retire vault-preprod + Kafka/n8n/platform + extra NS (nonprod only)
```

## Phase map

| Order | Track | Phase | File | Status |
|-------|-------|-------|------|--------|
| 0 | Dev | Backups + inventory | [phase-0.md](phase-0.md) | As executed |
| 1 | Dev | Remap + TF outline lock | [phase-1.md](phase-1.md) | As executed |
| 2 | Dev | Vault seed + dig apps/agents | [phase-2.md](phase-2.md) | As executed / laptop dig |
| 3 | Preprod | One Kind lean: CSI + AppSets + edge + drain Contabo dig | [phase-3.md](phase-3.md) | **Docs ready — implement when started** |
| 4 | Preprod | Prove lean fleets | [phase-4.md](phase-4.md) | Blocked until Phase 3 Grown |
| 5 | Preprod | Retire vault-preprod / Kafka / n8n / platform / extra NS | [phase-5.md](phase-5.md) | Blocked until Phase 4 Grown |

Tests: [`tests/`](tests/).

## Dev Grown (laptop dig — Phases 0–2)

Historical gate for dig Vault seed. Laptop dig SoT is **not** Contabo dig NS.

- [x] Phase 0 inventory (prod + preprod backups on disk)
- [x] Phase 1 remap + TF-OUTLINE for Contabo `apps/data/dev`
- [x] Phase 2 TF seed Contabo `apps/data/dev`
- [ ] Laptop dig apps + agents Ready (local Argo / `am-dev-apps`) — see DEV_ON_CONTABO.md
- [ ] Google login on dig UI

Phases 3–5 **do not require Contabo dig NS green**. They require Vault `apps/data/preprod` present (done) and operator confirm before any NS delete.

## Preprod Contabo Grown (after Phase 3–4)

- [ ] Phase 3: CSI on `vault.asrax.in`; AppSets Synced; edge minimal; Contabo dig NS drained
- [ ] Contabo Argo **preprod apps** → `am-apps-preprod` Ready
- [ ] Contabo Argo **preprod agents** → `am-agents-preprod` Ready
- [ ] Google login on Contabo preprod UI green
- [ ] Laptop dig unchanged; **prod Kind untouched**
- [ ] Phase 4 prove complete → Phase 5 retire allowed

## Loop

```text
Prereq → Implement (gitops + Contabo Argo / am gitops) → Test → Grown → next
```

Clean / NS delete: inventory → user confirm → double-check host + names → only then delete (am-kind-fleet rule).

## Refuse (whole track)

- Any change to Contabo **prod** Kind, prod AppSets, or `apps/data/prod`
- Surgery scripts (`*.ps1` / `*.sh`) as seed or retire SoT
- kubectl sync Applications (use `am gitops sync` / Contabo Argo API)
- Writing into `apps/data/prod`
- Pointing preprod CSI at `vault-preprod.asrax.in` after Phase 3b
- Kubernetes auth from Contabo Vault to Kind API (use JWT)
- Committing secret **values** into Git
- Seeding Kafka / n8n / platform onto lean Contabo preprod
- Re-adding Contabo dig NS after Phase 3e drain
- Deleting vault-preprod before Phase 4 Grown
- Touching laptop dig Kind as part of Phases 3–5
- hostAliases / Docker exposer IP pins on Contabo nonprod
