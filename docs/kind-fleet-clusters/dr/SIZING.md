# DR sizing + Kind node design

**Take DR config from:**

| What | Path |
|------|------|
| Pod CPU/mem/disk tables (**dr** rows) | [`docs/kind-fleet-resources/SIZING.md`](../kind-fleet-resources/SIZING.md) |
| TF SoT stores | `terraform/modules/core/store-sizing` (`environment=dr`) |
| TF SoT platform | `terraform/modules/core/platform-sizing` (`environment=dr`) |
| Wire-in | `terraform/kind-fleet/dr/stores` → `module.sizing` with `environment = local.env` (`dr`) |
| Host + Kind nodes | **this file** |
| Agent summary | skill `am-kind-fleet` `reference/sizing.md` |

**Default vs dr:** TF defaults elsewhere = **dev** row. VPS3 must use **`environment=dr`** — never apply prod tables on VPS3; never apply DR sizes on the laptop.

## Host class

| Class | When | vCPU | RAM | SSD |
|-------|------|------|-----|-----|
| **Current (use now)** | VPS3 warm DR | **8** | **32 GB** | **500 GB** |

State: `/data/am-state/terraform/dr/` on VPS3 only.

---

## Kind topology

Always **three** Kind clusters — **all one-node**:

| Cluster | Port | `node_shape` | Stack |
|---------|------|--------------|--------|
| `am-dr-infra` | 6443 | **`one`** | `kind-fleet/dr/infra` |
| `am-dr-apps` | 6444 | **`one`** | `kind-fleet/dr/apps` |
| `am-dr-platform` | 6445 | **`one`** | `kind-fleet/dr/platform` |

---

## DR store sizes (from TF — vs default/dev)

| Store | Default (**dev**) | **DR** (32 GB class) |
|-------|-------------------|----------------------|
| postgresql | 50m–500m / 256Mi–1Gi / 5Gi | **175m–1000m / 768Mi–2Gi / 16Gi** |
| mongodb | 50m–500m / 512Mi–1Gi / 5Gi | **175m–1000m / 768Mi–2Gi / 16Gi** |
| redis | 50m–200m / 256Mi–512Mi / 1Gi | **100m–400m / 256Mi–1Gi / 4Gi** |
| kafka | 50m–500m / 512Mi–1Gi / 5Gi | **140m–1000m / 768Mi–2Gi / 10Gi** |
| influxdb | 50m–500m / 512Mi–1Gi / 5Gi | **70m–500m / 768Mi–2Gi / 5Gi** |
| minio | 50m–500m / 256Mi–512Mi / 5Gi | **140m–1000m / 384Mi–2Gi / 20Gi** |
| vault | 50m–200m / 128Mi–256Mi | **70m–500m / 192Mi–512Mi** |

Full platform table: [`kind-fleet-resources/SIZING.md`](../kind-fleet-resources/SIZING.md) — use **dr** rows only on VPS3.

---

## Checkboxes

- [ ] Host **8 vCPU · 32 GB · 500 GB**.
- [ ] Three Kind names; **all `node_shape=one`**.
- [ ] Stores/platform `environment=dr` (not prod, not dev defaults).
- [ ] Spot-check requests match **dr** column after Phase 2/3.

## Refuse

- Applying **prod** store/platform sizes on VPS3.
- Applying **dr** sizes from the laptop.
- Two-node infra on DR.
- Shrinking mid Phase 2–5.
