# PROD deploy — Kind fleet on VPS1

**Checkbox SoT for prod:** [`prod/`](prod/) (all unchecked until executed).  
**Agent playbook:** skill **`am-kind-fleet`** (`amctl/ai-catalog/skills/platform/am-kind-fleet/`).  
**Historical multi-env pack:** [TODO.md](TODO.md) (laptop/dev progress — do not wipe).

Docs only until you confirm Execute. No terraform/Kind apply from this pack alone.

## Locked

| Item | Value |
|------|--------|
| Host | VPS1 Contabo (`VPS_IP` from `VPS/.env`) |
| Env token | `prod` |
| Clusters | `am-prod-infra` :6443 · `am-prod-apps` :6444 · `am-prod-platform` :6445 |
| Kind nodes (serve-first 64 GB) | Infra **`two`**; apps/platform **`one`** — three names `am-prod-{infra,apps,platform}` |
| Kind nodes (optional later) | After obs offload / shrink — see [prod/SIZING.md](prod/SIZING.md) |
| TF state | `/data/am-state/terraform/prod/` on **VPS1 only** |
| Day-2 | `am-ops` / `am-vps1-ops` · Kind create/stop = G1 |
| Vault apps | **terraform** `kind-fleet/prod/vault-apps` |
| Product pods | **Argo** from `am-gitops` `main` |
| Access (2–4) | `access_enforce=false`, `mfa_enforce=false` |
| Seed | R2 `asrax-disaster` / `disaster/latest` PG+Mongo+Redis; Influx = TF + `sync-influx-vps.ps1` |
| Sizing | **Serve first:** `environment=prod` on **8c/64GB/500** — [prod/SIZING.md](prod/SIZING.md) |
| VPS1 hardware | **8 vCPU · 64 GB · 500 GB SSD** (current). Shrink 6/36 only after prod green + obs room |

## Sequence (prod)

```text
P → 0 → C (VPS1 confirm) → 5.1 am-ops → 1 validate
  → 2 Edge→stores→seed (2A–2I) → 3 platform/3e → 4 Vault TF + Argo
  → ZT-P0 enroll (after 3) · ZT-P1 later (with Phase 10)
```

| Order | Phase | File |
|-------|-------|------|
| 1 | P / 0 / C | [prod/phase-p-0-c.md](prod/phase-p-0-c.md) |
| 2 | 5.1 VPS security | [prod/phase-5.md](prod/phase-5.md) |
| 3 | 1 TF validate | [prod/phase-1.md](prod/phase-1.md) |
| 4 | 2 infra + seed | [prod/phase-2.md](prod/phase-2.md) |
| 5 | 3 platform | [prod/phase-3.md](prod/phase-3.md) |
| 6 | 4 apps | [prod/phase-4.md](prod/phase-4.md) |
| 7 | ZT window | [prod/phase-zt.md](prod/phase-zt.md) |

Detail: [prod/README.md](prod/README.md) · [prod/SIZING.md](prod/SIZING.md) (take **prod** rows from [kind-fleet-resources/SIZING.md](../kind-fleet-resources/SIZING.md); default TF row = **dev**).

## Start order (serve-first 64 GB)

```text
P → 0 → C → 5.1 → 1 → 2 → 3 → 4 → ZT-P0
```

Checkbox SoT: `prod/phase-*.md`. Mark boxes as you go. Sizing: always `environment=prod` on VPS1.

## Not in this pack (pointers)

- DR / failback: TODO Phases 6–9 · skill `reference/phase-6-12.md`
- VPS2 obs: Phase 11 · `OBS_VPS2_SIZING.md`
- Failover drill: Phase 12

## Refuse

- `--env local` / `preprod` / apply `terraform/**/{local,preprod}`
- Laptop as SoT for prod TF state
- Seed before Phase 2 **2F** green; seed from laptop folder; Influx from R2
- Port-forward / localhost as Test
- Terraform for AM Deployments; Argo writing Vault
- Access enforce mid Phase 2–4
- Kind create before Phase 5.1 green
- Keeping infra **2-node** after move to **6c/36GB** (use all 1-node — [prod/SIZING.md](prod/SIZING.md))
- Full prod request tables on 36 GB without compact profile
