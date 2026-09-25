# Prod sizing + Kind node design

**Take prod config from:**

| What | Path |
|------|------|
| Pod CPU/mem/disk tables (dev vs **prod** vs dr) | [`docs/kind-fleet-resources/SIZING.md`](../kind-fleet-resources/SIZING.md) |
| TF SoT stores | `terraform/modules/core/store-sizing` (`environment=prod`) |
| TF SoT platform | `terraform/modules/core/platform-sizing` (`environment=prod`) |
| Wire-in | `terraform/kind-fleet/prod/stores` → `module.sizing` with `environment = local.env` (`prod`) |
| Host + Kind nodes | **this file** |
| Agent summary | skill `am-kind-fleet` `reference/sizing.md` |

**Default vs prod:** TF module comments say “defaults elsewhere = **dev** row”. Laptop/`kind-fleet/dev` uses `environment=dev`. VPS1 must use **`environment=prod`** — never apply prod tables on the laptop.

## Priority: serve first on 64 GB

Do **not** shrink hardware until prod writer is green. Later: obs offload frees room; optional 6c/36GB after that.

| Class | When | vCPU | RAM | SSD |
|-------|------|------|-----|-----|
| **Current (use now)** | VPS1 stand-up | **8** | **64 GB** | **500 GB** |
| Optional later | After obs offload | 6 | 36 GB | 500 GB |

State: `/data/am-state/terraform/prod/` on VPS1 only.

---

## Kind topology (serve-first)

Always **three** Kind clusters:

| Cluster | Port | `node_shape` | Stack |
|---------|------|--------------|--------|
| `am-prod-infra` | 6443 | **`two`** | `kind-fleet/prod/infra` |
| `am-prod-apps` | 6444 | **`one`** | `kind-fleet/prod/apps` (`node_shape=one`) |
| `am-prod-platform` | 6445 | **`one`** | `kind-fleet/prod/platform` (`node_shape=one`) |

---

## Prod store sizes (from TF — vs default/dev)

| Store | Default (**dev**) CPU / mem / disk | **Prod** CPU / mem / disk |
|-------|-------------------------------------|---------------------------|
| postgresql | 50m–500m / 256Mi–1Gi / **5Gi** | **250m–1000m / 1Gi–2Gi / 16Gi** |
| mongodb | 50m–500m / 512Mi–1Gi / 5Gi | **250m–1000m / 1Gi–2Gi / 16Gi** |
| redis | 50m–200m / 256Mi–512Mi / 1Gi (max **256mb**) | **100m–400m / 256Mi–1Gi / 4Gi (max 768mb)** |
| kafka | 50m–500m / 512Mi–1Gi / 5Gi | **200m–1000m / 1Gi–2Gi / 10Gi** |
| influxdb | 50m–500m / 512Mi–1Gi / 5Gi | **100m–500m / 1Gi–2Gi / 5Gi** |
| minio | 50m–500m / 256Mi–512Mi / 5Gi | **200m–1000m / 512Mi–2Gi / 20Gi** |
| vault | 50m–200m / 128Mi–256Mi | **100m–500m / 256Mi–512Mi** |

Full platform table (Keycloak, Argo, Temporal, Lago, …): [`kind-fleet-resources/SIZING.md`](../kind-fleet-resources/SIZING.md) — use **prod** rows only on VPS1.

---

## Checkboxes

### Serve-first (now)

- [ ] Host **8 vCPU · 64 GB · 500 GB**.
- [ ] Three Kind names; infra **two**; apps/platform **one**.
- [ ] Stores/platform `environment=prod` (not dev defaults).
- [ ] Spot-check requests match **prod** column after Phase 2/3.

### Later

- [ ] Obs resized / infra-adjacent load moved off VPS1.
- [ ] Only then evaluate 6c/36GB.

## Refuse

- Applying **dev** store/platform sizes on VPS1.
- Applying **prod** sizes from the laptop.
- Shrinking mid Phase 2–4.
- Prod apps/platform without `node_shape=one`.
