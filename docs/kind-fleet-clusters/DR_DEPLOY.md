# DR deploy — Kind fleet on VPS3

**Checkbox SoT for DR:** [`dr/`](dr/) (unchecked until executed).  
**Agent playbook:** skill **`am-kind-fleet`** (`amctl/ai-catalog/skills/platform/am-kind-fleet/`).  
**Historical multi-env pack:** [TODO.md](TODO.md) (do not wipe).  
**Prod track:** [PROD_DEPLOY.md](PROD_DEPLOY.md) · [`prod/`](prod/).  
**Target delta (1 Kind DR, R2 slave, same-domain CF cutover):** [`identity-infra-split/`](identity-infra-split/) — especially [phase-6.md](identity-infra-split/phase-6.md) + [FAILOVER.md](identity-infra-split/FAILOVER.md). Do not rewrite finished `dr/` history boxes; new target lives in the delta track.

Docs + code scaffolding first. No terraform/Kind/CF LB mutate until you confirm Execute on VPS3.

## Locked

| Item | Value |
|------|--------|
| Host | VPS3 (`VPS_3_IP` from `VPS/.env`) |
| Env token | `dr` |
| Clusters (historical stand-up) | `am-dr-infra` :6443 · `am-dr-apps` :6444 · `am-dr-platform` :6445 |
| **Target (identity-infra-split)** | **1** Kind — DBs + platform NS via R2 auto-sync; public cutover = services on **same** prod domains (no `*-dr` DB/platform DNS) |
| Kind nodes | **All `one`** — three names `am-dr-{infra,apps,platform}` |
| TF state | `/data/am-state/terraform/dr/` on **VPS3 only** |
| Day-2 | `am-ops` / `am-vps3-ops` · Kind create/stop = G1 |
| Kind lifecycle | **Create once.** Later phases **import/adopt** into TF — **never** `kind delete` just to apply Vault/CSI/Argo. Wipe only via explicit Phase C / break-glass. |
| Vault apps | **terraform** `kind-fleet/dr/vault-apps` → `apps/data/dr/…` |
| Product pods | **Argo** from `am-gitops` `main` (`dr/` pins + ApplicationSets) |
| Access (2–5) | `access_enforce=false`, `mfa_enforce=false` |
| Seed | R2 `asrax-disaster` / `disaster/latest` PG+Mongo+Redis; Influx = TF + sync script |
| Sizing | `environment=dr` on **8c/32GB/500** — [dr/SIZING.md](dr/SIZING.md) |
| Replica | G20 PG standby + Mongo secondary over WireGuard VPS1↔VPS3 |
| Failover | CF LB VPS1 primary / VPS3 fallback on `am`+`auth`; **auto-failback off** |

## Sequence (DR)

```text
P → 0 → C (VPS3) → 5.1 am-ops + 5.3 WG → 1 validate
  → 2 Edge→stores→seed → 3 platform/3e
  → 4 Vault sync (all apps) → 5 Argo deploy/sync/verify
  → 6 G20 + CF LB → ZT-P0 (after 3)
```

| Order | Phase | File |
|-------|-------|------|
| 1 | P / 0 / C | [dr/phase-p-0-c.md](dr/phase-p-0-c.md) |
| 2 | 5.1 VPS + 5.3 WG | [dr/phase-5.md](dr/phase-5.md) |
| 3 | 1 TF validate | [dr/phase-1.md](dr/phase-1.md) |
| 4 | 2 infra + seed | [dr/phase-2.md](dr/phase-2.md) |
| 5 | 3 platform | [dr/phase-3.md](dr/phase-3.md) |
| 6 | **4 Vault sync** | [dr/phase-4.md](dr/phase-4.md) |
| 7 | **5 Argo waves** | [dr/phase-5-argo.md](dr/phase-5-argo.md) |
| 8 | 6 G20 + CF LB | [dr/phase-6-g20-lb.md](dr/phase-6-g20-lb.md) |
| 9 | ZT window | [dr/phase-zt.md](dr/phase-zt.md) |

Detail: [dr/README.md](dr/README.md) · [dr/SIZING.md](dr/SIZING.md).

## Phase 4 vs Phase 5 (apps split)

| Phase | Owns | Refuse |
|-------|------|--------|
| **4 Vault** | `kind-fleet/dr/vault-apps` once + G25 CSI/auth | Hand-seed Vault; Argo writing Vault; product pods |
| **5 Argo** | Register cluster, enroll AppSets/roots, sync waves 5c–5g, domain verify | Terraform AM Deployments; default `am deploy` |

## Not in this pack (pointers)

- Phase 7 promote / freeze VPS1 · Phase 8 rebuild VPS1 · Phase 9 failback · Phase 12 drill — [TODO.md](TODO.md) / skill `reference/phase-6-12.md`
- VPS2 obs: Phase 11 · [OBS_DEPLOY.md](OBS_DEPLOY.md) · [`obs/`](obs/) · [OBS_VPS2_SIZING.md](OBS_VPS2_SIZING.md)

## Refuse

- `--env local` / `preprod` / apply `terraform/**/{local,preprod}`
- Laptop as SoT for DR TF state
- Seed before Phase 2 **2F** green; Influx from R2
- Port-forward / localhost as Test
- Terraform for AM Deployments; Argo writing Vault
- Access enforce mid Phase 2–5
- Kind create before Phase 5.1 green
- Dual writer; R2 restore onto live G20 replica; CF auto-failback
- `am-apps-prod` namespace on VPS3
- **Disposable surgery scripts** (`dr-phase*.sh`, `tmp-*`). Fail → am-gitops/TF PR → `argocd app sync` → `phase_gates --env dr --wave …` only

## Phase 5 operator loop (same as prod)

1. Desired state gap → **am-gitops** `overlays/dr/extra-*` or AppSet (or TF for edge/Vault/middleware).
2. Merge `main`.
3. `argocd app sync <service>-dr` (Manual; platform cluster CLI when MCP write off).
4. `PYTHONPATH=scripts/kind-fleet python -m phase_gates --env dr --wave 4d|4e|4f|4g`.

DR AppSets load `values.prod.yaml` so missing `values.dr.yaml` still inherits prod probes; overlays remap `apps/data/dr/*` + `am-dr.asrax.in`.
