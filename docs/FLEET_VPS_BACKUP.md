# Fleet / backup plan (parked for next session)

**Host remap (locked):** `VPS_IP` = prod · `VPS_2_IP` = Grafana/obs · `VPS_3_IP` = DR. Live pack: [kind-fleet-clusters/PLAN.md](kind-fleet-clusters/PLAN.md).

**Saved:** 2026-09-23 · **Resume:** tomorrow — start at “What to do now”

Cursor plan file (same content): `c:\Users\user\.cursor\plans\three_vps_sizing_71a89af3.plan.md`

---

## What to do now (protect development + stabilize prod)

Do **not** buy VPS2/VPS3/PP-DR yet. Fix Contabo prod slim rebuild first, while **preprod/dev stay on their own box**.

### Order of operations

1. Verify preprod/dev isolated from Contabo
2. Laptop dumps / Vault backup safe
3. Rebuild Contabo prod-only slim
4. Prove prod and dev both work
5. Later: VPS3 DR, PP-DR, R2, Grafana on VPS2

### 1. Protect development (first)

| Action | Why |
|--------|-----|
| Kind/preprod = **local** Vault/Mongo/Redis/Kafka — not Contabo | Contabo work must not break preprod |
| Nonprod kubeconfig for daily Cursor/amctl | Avoid empty Contabo during rebuild |
| Develop against preprod URLs / Kind | Prod can stay flaky |
| Cut Contabo coupling if still present | See am-gitops `docs/CLUSTER_ISOLATION.md` |

**Rule:** Shared preprod = **VPS-PP** / **VPS-PP-DR**. Prod = **Contabo**. Never share stores.

### When VPS-PP is down (dev must not stop for days)

| Failure | Restore same PP? | Developers use |
|---------|------------------|----------------|
| Kind broken, host up | Yes — R2 `preprod/` | Local Kind meanwhile |
| Host down for days | No | **VPS-PP-DR** + local Kind |

| Priority | Env |
|----------|-----|
| 1 | Local Kind / amctl (same day) |
| 2 | VPS-PP-DR 16GB — restore R2 `preprod/`, CF preprod tunnel |
| 3 | Fail back to VPS-PP when host returns |
| Never | Contabo / VPS1 / VPS2 / VPS3 |

### VPS-PP-DR sizing

- **16 GB** RAM, 4–8 vCPU, 200–400 GB disk
- Preprod only — not prod DR
- Idle until PP host dead; then R2 restore

### 2. Before Contabo rebuild

- Laptop dumps (`am-data-backup` / `BACKUP_ROOT`)
- Vault snapshot on laptop
- PKI on host volume before any Kind wipe

### 3. Contabo prod stable (Phase 0)

Redeploy only: Kind + PKI on host → Vault → Keycloak → infra-prod ×1 → am-apps-prod + core AI → Alloy → prod tunnel.

**Do not** redeploy: infra-dev/preprod, billing, GrowthBook, triple Kafka.

**Targets:** ≥16 GiB RAM free, disk &lt;70%, CPU &lt;70%.

### 4. Prove both

- Preprod works on Kind
- Prod critical path on Contabo
- Preprod does not depend on Contabo stores
- Contabo no OOM/reboot loop

### 5. Later (after prod stable)

- VPS3 **32 GB** prod DR (degraded promote) + backup jobs
- VPS-PP-DR **16 GB**
- VPS2 Grafana 16–32 GB
- R2 `prod/` + `preprod/` + later edge reads

---

## Target fleet

| Host | Role | Size |
|------|------|------|
| VPS1 Contabo | Prod primary | ~64 GB |
| VPS2 (`VPS_2_IP`) | Grafana / obs | 16–32 GB |
| VPS3 (`VPS_3_IP`) | Prod DR + backups | **32 GB** degraded |
| VPS-PP | Preprod primary | Existing; slim; isolated |
| VPS-PP-DR | Preprod standby | **16 GB** |
| R2 | Backup files only | `prod/` + `preprod/` |
| Local Kind | Solo / same-day | Laptop |

### Keycloak if VPS1 down 48h

- Primary Keycloak on VPS1
- Standby Keycloak on VPS3 (with identity DB)
- CF fails over **apps + auth** together
- No separate Keycloak-only VPS for now

### R2 (reminder)

Cloudflare object storage for dumps — not a live env.

```text
R2 bucket
├── prod/mongo|vault/...
└── preprod/mongo|vault/...
```

---

## Resume checklist (tomorrow)

- [ ] Confirm preprod isolated from Contabo
- [ ] Confirm laptop dumps / Vault backup
- [ ] Phase 0 Contabo slim prod rebuild
- [ ] Prove preprod + prod both healthy
- [ ] Then size/order VPS3 32GB (DR) and VPS-PP-DR 16GB
