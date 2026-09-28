# Phase 3 — Lean Contabo nonprod: one Kind + CSI to prod Vault

**Status:** Docs ready — implement when operator starts (Vault `apps/data/preprod` already restored).

**Goal:** Collapse Contabo **nonprod** to **one Kind** with **three namespaces** (`am-apps-preprod`, `am-agents-preprod`, edge). Switch CSI to Contabo prod Vault (`vault.asrax.in` + JWT) like dig. Enroll lean apps + agents AppSets via Contabo Argo. Drain Contabo dig NS. **Do not touch prod Kind.**

**Prereq:** `apps/data/preprod/*` on `https://vault.asrax.in` (done 2026-09-28 — see [INVENTORY.md](INVENTORY.md)). Contabo Argo `https://argocd.asrax.in`. Operator kubeconfig for Contabo nonprod (not laptop dig).

**Target shape:**

| Item | Value |
|------|--------|
| Kind | One — `am-vps-nonprod` |
| NS keep | `am-apps-preprod`, `am-agents-preprod`, edge (`traefik` + `cloudflared`) |
| Vault CSI | `https://vault.asrax.in` + `auth/jwt-nonprod` → `apps/data/preprod/*` |
| Stores | `postgres\|mongo\|redis\|kafka.asrax.in` |
| Contabo dig NS | Drain / delete after AppSets stopped |
| Laptop dig | Untouched |
| Prod Kind | Untouched |

**Gitops model (prod-fleet shape):**

| Prod (reference) | Contabo **preprod** (this phase) |
|------------------|----------------------------------|
| [apps-prod-fleet.yaml](../../../../am-gitops/application-sets/apps-prod-fleet.yaml) | Preprod apps AppSet → `am-vps-nonprod` / **`am-apps-preprod`** |
| [agents-prod-fleet.yaml](../../../../am-gitops/application-sets/agents-prod-fleet.yaml) | Preprod agents AppSet → `am-vps-nonprod` / **`am-agents-preprod`** |
| Contabo Approve / `am gitops` | Contabo Approve rolls helm image tag (no pin commit) |
| CSI `apps/data/prod` | CSI `apps/data/preprod` + JWT (mirror [overlays/dev/vault-https-contabo.yaml](../../../../am-gitops/overlays/dev/vault-https-contabo.yaml)) |

```text
inventory nonprod (no delete)
  → JWT + overlay vault.asrax.in (keep vault-preprod until Phase 5)
  → Contabo Argo AppSets: apps + agents → am-*-preprod
  → edge NS minimal (Traefik + cloudflared)
  → drain Contabo dig NS (user confirm before delete)
  → Phase 3 Grown → Phase 4 prove
```

## Implement

### 3a — Inventory Contabo nonprod (no delete yet)

- [x] List Kind clusters on Contabo nonprod host
- [x] List namespaces + Contabo Argo Applications targeting `am-vps-nonprod`
- [x] Mark **keep:** `am-apps-preprod`, `am-agents-preprod`, edge
- [x] Mark **remove** in [INVENTORY.md](INVENTORY.md): Contabo `am-apps-dev` / `am-agents-dev`, vault-preprod workloads, Kafka / n8n / platform, extra NS
- [x] Vault seed `apps/data/preprod/*` — **Done 2026-09-28** (backup restore + host remap). Do **not** re-run TF seed unless drift-managed ownership is added later

Optional later TF ownership (drift-managed):

- [ ] Contabo vault-apps TF root for `env=preprod` — address `https://vault.asrax.in`, separate state
- [ ] Lean skips per [PATH_REMAP.md](PATH_REMAP.md) if re-seeding from TF
- [ ] `terraform plan` — only `preprod/…`; **zero** `prod/` or dig overwrite

### 3b — CSI switch to Contabo Vault (mirror dig)

- [x] JWT role/policy for preprod SA on `auth/jwt-nonprod` (`am-backend-role-preprod` → `apps/data/preprod/*`); Contabo Kind JWKS merged into jwt-nonprod
- [x] Replace [overlays/preprod/vault-https-preprod.yaml](../../../../am-gitops/overlays/preprod/vault-https-preprod.yaml) / fleet-common: `vault-preprod.asrax.in` + kubernetes auth → `vault.asrax.in` + JWT + `audience: vault` (pushed `057acb6`)
- [x] Do **not** delete vault-preprod yet (rollback until Phase 5)

### 3c — Preprod apps via Contabo Argo (prod-fleet shape)

- [x] Add / enroll Contabo ApplicationSet for **preprod apps** (`application-sets/apps-preprod-fleet.yaml`): `destName=am-vps-nonprod`, `destNamespace=am-apps-preprod`
- [x] ValueFiles: Contabo Vault JWT overlay + lean extras; `ignoreApplicationDifferences` on helm.parameters
- [ ] Sync via Contabo Argo — repo-server lock cleared; **fleet sync still settling** (re-check SPC/pod Ready)
- [ ] Verify: Contabo Argo Applications Healthy/Synced for enrolled **apps**
- [ ] Verify: pods Ready in `am-apps-preprod`; CSI mounts OK

### 3d — Preprod agents via Contabo Argo (prod-fleet shape)

- [x] Add / enroll Contabo ApplicationSet for **preprod agents** (`application-sets/agents-preprod-fleet.yaml`): `destNamespace=am-agents-preprod`
- [x] Exclude n8n / Kafka-dependent / platform agents; exclude ai-gateway (pilot)
- [x] NS `am-agents-preprod` + `am-backend-sa` created
- [ ] Sync via Contabo Argo / verify agents Ready in `am-agents-preprod`

### 3e — Edge NS minimal

- [x] Confirm Traefik + cloudflared-asrax-preprod Ready in **`infra`** (no separate edge NS yet — Phase 5 shrink)
- [ ] Preprod IngressRoutes terminate via that Traefik only (spot-check)
- [ ] Spot-check tunnel → Traefik → preprod Service path

### 3f — Drain Contabo dig (not laptop dig)

- [x] Soft-delete Contabo Argo `dev-apps-root` + orphan `*-dev` Apps (dest `am-dev-apps` missing)
- [x] Inventory Contabo dig NS still has orphan pods → **ask user confirm** before NS delete
- [ ] After confirm: delete Contabo NS `am-apps-dev` and `am-agents-dev` only
- [x] Laptop `am-dev-apps` unchanged; prod Kind unchanged

### 3g — Gitops lean cut (still no delete of vault-preprod)

- [ ] Disable Contabo Argo Applications for preprod Kafka / n8n / platform (gitops only) — Phase 5 primarily
- [ ] Prove Google login on Contabo **preprod** UI after CSI switch (Phase 4)

## Test

Use [tests/phase-3.md](tests/phase-3.md).

## Grown

- [ ] Inventory complete; remove-candidates filled in INVENTORY
- [ ] CSI on Contabo Vault (JWT); overlay no longer points at vault-preprod for enrolled apps
- [ ] Preprod **apps** fleet Synced/Healthy → `am-apps-preprod` Ready
- [ ] Preprod **agents** fleet Synced/Healthy → `am-agents-preprod` Ready
- [ ] Edge = Traefik + cloudflared only (minimal)
- [ ] Contabo dig NS drained (or delete confirmed)
- [ ] vault-preprod still available for rollback until Phase 5
- [ ] Laptop dig unchanged; **prod Kind untouched**

## Stop if fail

CSI fail or AppSet unhealthy → roll vault overlay back to `vault-preprod` **before** any delete; do not open Phase 5.

## Refuse

- Execute Phase 5 deletes in this phase
- Seeding kafka/n8n/platform onto Contabo preprod paths
- kubectl sync / surgery scripts as SoT
- Deleting vault-preprod in this phase
- Writing into `apps/data/prod` or mutating Contabo **prod** Kind
- Deleting Contabo dig NS without user confirm
- Touching laptop dig Kind
