# Identity / infra split + fleet Kind target

Delta track beside [`prod/`](../prod/). **Does not rewrite** finished prod Phase 1–4 history boxes.

Index: [PROD_DEPLOY.md](../PROD_DEPLOY.md) · [DR_DEPLOY.md](../DR_DEPLOY.md) · [TODO.md](../TODO.md)  
Sizing: [SIZING.md](SIZING.md) · Failover: [FAILOVER.md](FAILOVER.md) · TF notes: [TF-OUTLINE.md](TF-OUTLINE.md) · Inventory: [INVENTORY.md](INVENTORY.md)

## Recommendation (locked)

**Contabo: 2 Kind + 1 DB stack.** Platform tools = namespaces on infra. Apps Kind talks to the **same** stores. No second Contabo DB fleet for “platform vs apps.”

**Terraform-first:** Kind, stores, platform move, Vault, dump→R2 and DR pull are **TF modules / resources** (including TF-managed CronJob/Job). Operator path = `terraform apply` order in phases — **not** ad-hoc surgery `*.ps1` / `*.sh`.

## Kind counts

| Host | Kind | Layout |
|------|------|--------|
| Contabo **prod** | **2** | `am-prod-infra` :6443 = stores + Keycloak + Vault + Traefik + platform NS; `am-prod-apps` :6444 = services |
| **DR** VPS | **1** | DBs + platform NS warm via R2; cutover = **services** on same domains |
| **Nonprod** | **1** | Stores + KC + apps (lean); no full Lago/Temporal/n8n |

**Drop:** `am-prod-platform` :6445 (and multi-Kind on DR/nonprod).

## Locked decisions

| Item | Value |
|------|--------|
| Stores | **One** stack on Contabo (`infra` NS); shared by platform tools + apps |
| Keycloak | On **infra**; JDBC `postgres.asrax.in` / DB `platform` / schema `keycloak` |
| Vault | **One** on Contabo; paths `apps/data/prod/…` and `preprod/…` |
| Lago | Prod (+ DR warm) only |
| R2 | Continuous prod dump → `asrax-disaster`; DR **auto-sync** DBs + platform (master→slave) |
| Domains / creds | **Same** as prod on failover — **no** public `*-dr` DB/platform endpoints |
| DR public role | **Services only** after CF cutover |
| Preprod retire | Backup → nonprod DB sync **before** delete |
| DR track | Off until Contabo Phases 1–3 green; then Phase 6 |

```text
Contabo:  infra (1 DB stack + KC + Vault + platform NS) + apps
DR:       1 Kind — R2 slave DBs/platform; CF points same domains at services
Nonprod:  1 Kind lean — after preprod backup sync
```

## Phase map

| Order | Phase | File |
|-------|-------|------|
| 0 | Inventory | [phase-0.md](phase-0.md) |
| 1 | Infra + Keycloak + Vault | [phase-1.md](phase-1.md) |
| 2 | Platform tools on infra; retire platform Kind | [phase-2.md](phase-2.md) |
| 3 | Prod apps prove | [phase-3.md](phase-3.md) |
| 4 | Nonprod 1 Kind + preprod handoff | [phase-4.md](phase-4.md) |
| 5 | Harden + continuous R2 dump | [phase-5.md](phase-5.md) |
| 6 | DR warm slave + CF services cutover | [phase-6.md](phase-6.md) |

Tests: [`tests/`](tests/).

## Loop

```text
Prereq → Implement (terraform apply order) → mcp-sync (when needed) → Test → Grown → next
```

## Refuse (whole track)

- Third Kind on Contabo (`am-prod-platform`)
- Second Contabo DB stack for platform
- Public `*-dr.asrax.in` for postgres/mongo/platform
- Full preprod platform on Contabo or nonprod
- Second Vault; Authentik
- Delete preprod without backup evidence
- Rewriting finished `prod/phase-*.md` history
- Ad-hoc surgery scripts as SoT (use TF modules instead)
- Live Kind/TF/CF mutate until an explicit later Execute for cutover
