# VPS2 obs sizing + retention (Phase 11)

**Host:** prefer **≥16 GB** if platform third-parties colocated ([VPS2_DEV_PLATFORM.md](VPS2_DEV_PLATFORM.md)); obs-only floor **4 vCPU / 8 GB / ~200 GB SSD**.  
**Stack:** Grafana + Loki + Prometheus + Tempo (+ Alloy local + Traefik/edge). When hub expands: Vault (`apps/data/dev` SoT) + OpenProject / Lago / Langfuse / n8n / GrowthBook / …  
**TODO:** [TODO.md](TODO.md) Phase 11 + **11b**.  

**Role:** VPS2 = **ops / shared platform + credentials hub** — not Grafana-only. Laptop Kind is optional lab.

---

## Public FQDNs (no env suffix)

VPS2 owns these **bare** hostnames — **no** `-dev` / `-prod` / `-dr`:

| Role | FQDN |
|------|------|
| UI (ops access) | `https://grafana.asrax.in` |
| Logs push | `https://loki.asrax.in` |
| Metrics remote_write | `https://prometheus.asrax.in` |
| Traces | `https://tempo.asrax.in` |

**Shared ingest:** prod, DR, preprod (and laptop after cutover) Alloy / am-logging all push to the same Loki / Prometheus / Tempo URLs. Distinguish sources with labels (`environment`, `cluster`), not hostname.

**Laptop Kind** currently hosts these bare FQDNs as an interim hub ([GRAFANA_FLEET_DEV.md](GRAFANA_FLEET_DEV.md)) until Phase 11 moves the stack to VPS2 — same names, no cutover rename.

---

## Host budget (obs slice)

If only Grafana/Loki/Prom/Tempo run on an 8 GB box:

| Slice | Approx |
|-------|--------|
| OS + Docker + Kind + kube-system | ~1.5–2.0 GB |
| Usable for obs pods | ~6.0–6.5 GB |
| Disk for PVCs | ~150–170 GB (leave ~30 GB free) |

**With platform hub (11b):** keep obs PVC table below; add headroom for Vault + PG + OpenProject/Lago/Langfuse/n8n/GB — target **16 GB+** host RAM or do not colocate.

---

## Retention (auto-clear older than)

| Signal | Keep | Clear older than | Notes |
|--------|------|------------------|--------|
| **Prometheus (metrics)** | **30 days** | after 30d | Cheap vs logs/traces; **do not** shorten under log pressure |
| **Loki (logs)** | **14 days** | after 14d + **janitor** | Multi-env ship from many pods |
| **Tempo (traces)** | **5 days** | after 5d | Highest growth; cut first if disk pressure |

Loki: `chunksCache` / `resultsCache` **off** on this box.

---

## Log cleanup (two layers)

Retention alone is not enough under ingest spikes. Phase 11 must ship **both**:

1. **Loki retention + compactor** — continuous delete of chunks older than **14d**.
2. **CronJob `log-janitor`** — every **6h**:
   - Check Loki PVC usage.
   - If PVC **≥ 80%** full **or** on every run: force cleanup of data **older than retention** so free space returns even after a limit hit.
   - Log success/failure to stdout (scraped into Loki).

Janitor prioritizes **Loki**. Tempo relies on its own 5d retention; janitor disk check may include Tempo PVC as secondary. **Never** shorten Prometheus **30d** from the janitor.

---

## Pod resources + PVC

| Component | CPU req → lim | Mem req → lim | PVC |
|-----------|---------------|---------------|-----|
| Grafana | `200m` → `750m` | `512Mi` → `1Gi` | 10 Gi |
| Loki | `400m` → `1500m` | `1.5Gi` → `2.5Gi` | **80 Gi** |
| Prometheus | `200m` → `1000m` | `768Mi` → `1.5Gi` | **40 Gi** |
| Tempo | `250m` → `1000m` | `1Gi` → `2Gi` | **50 Gi** |
| Alloy (VPS2 local) | `50m` → `200m` | `128Mi` → `256Mi` | — |
| Traefik / edge | `50m` → `200m` | `64Mi` → `256Mi` | — |
| log-janitor CronJob | `50m` → `200m` | `64Mi` → `128Mi` | — (ephemeral) |

PVC total ≈ **180 Gi** → fits ~200 GB with OS/Docker headroom. Sum of **requests** should stay ≤ ~5.5–6 GB RAM.

---

## If OOM or disk pressure

1. Shorten **Tempo** retention (e.g. 5d → 3d).
2. Shorten **Loki** retention (e.g. 14d → 7d) and confirm janitor is running.
3. **Do not** cut Prometheus below **30d** unless metrics PVC itself is full.

---

## Related

- Phase 5.2 security: [PHASE5_VPS_SECURITY.md](PHASE5_VPS_SECURITY.md)
- VPS2 ops/dev + credentials hub: [VPS2_DEV_PLATFORM.md](VPS2_DEV_PLATFORM.md)
- Fleet Grafana interim (laptop): [GRAFANA_FLEET_DEV.md](GRAFANA_FLEET_DEV.md)
