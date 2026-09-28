# VPS2 obs sizing + retention (Phase 11)

**Checkbox SoT:** [`OBS_DEPLOY.md`](OBS_DEPLOY.md) · [`obs/`](obs/).  
**Host (locked):** **4 vCPU / 8 GB RAM / ~200 GB SSD** — obs hub only.  
**Runtime:** **Docker Compose — no Kind** (Kind + kube-system wasted ~1.5–2 GB on this box).  
**Stack:** Traefik + cloudflared + Grafana + Loki + Prometheus + Tempo + log-janitor.  
**No external DB** for Grafana or Loki.

**11b** (Vault `apps/data/dev`, OpenProject/…) needs **≥16 GB** — [VPS2_DEV_PLATFORM.md](VPS2_DEV_PLATFORM.md). **Refuse** 11b on this 8 GB host.

**TODO historic:** [TODO.md](TODO.md) Phase 11 — prefer marking boxes in [`obs/`](obs/).

**Role:** VPS2 = **shared log/metrics/traces hub** for all envs. Laptop Kind interim only until cutover ([GRAFANA_FLEET_DEV.md](GRAFANA_FLEET_DEV.md)).

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

**Laptop Kind** currently hosts these bare FQDNs as an interim hub until Phase 11 moves the stack to VPS2 — same names, no cutover rename.

---

## Where data lives (no external DB)

| Component | External DB? | Path on VPS2 |
|-----------|--------------|--------------|
| Loki (logs) | No — filesystem chunks/index | `/data/am-state/obs/loki/` |
| Grafana | No — SQLite (UI/config only) | `/data/am-state/obs/grafana/` |
| Prometheus | No — local TSDB | `/data/am-state/obs/prometheus/` |
| Tempo | No — blocks on disk | `/data/am-state/obs/tempo/` |

Grafana **queries** Loki/Prom/Tempo; it does **not** store fleet logs.

---

## Host budget (obs slice)

| Slice | Approx |
|-------|--------|
| OS + Docker (no Kind) | ~0.6–0.8 GB |
| Traefik + cloudflared | ~150–250 MB |
| Usable for Grafana/Loki/Prom/Tempo | ~6.0–6.5 GB |
| Leave free / page cache | ~1 GB |
| Disk free / OS / images | **≥40–50 Gi** |

Compose `mem_limit` sum **≤ ~6.5 GB**.

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

1. **Loki retention + compactor** — continuous delete of chunks older than **14d**.
2. **log-janitor** (Compose cron / sidecar) every **6h**:
   - Check Loki volume usage.
   - If volume **≥ 80%** full **or** on every run: force cleanup older than retention.
   - Log success/failure to stdout.

Janitor prioritizes **Loki**. Tempo uses its own 5d retention. **Never** shorten Prometheus **30d** from the janitor.

---

## Container resources + volumes

| Component | CPU lim | Mem lim | Volume |
|-----------|---------|---------|--------|
| Grafana | ~0.5 | 512Mi–1Gi | **5–10 Gi** |
| Loki | ~1.0–1.2 | 1.5–2.0 Gi | **60–70 Gi** |
| Prometheus | ~0.75 | 768Mi–1.2Gi | **30–35 Gi** |
| Tempo | ~0.75 | 1–1.5 Gi | **30–40 Gi** |
| Traefik / cloudflared | ~0.25 | ≤256Mi | — |
| log-janitor | ~0.2 | ≤128Mi | — |

Volume total ≈ **125–155 Gi** data + ≥40–50 Gi free on ~200 GB.

---

## If OOM or disk pressure

1. Shorten **Tempo** retention (e.g. 5d → 3d).
2. Shorten **Loki** retention (e.g. 14d → 7d) and confirm janitor is running.
3. **Do not** cut Prometheus below **30d** unless metrics volume itself is full.

---

## Related

- Deploy pack: [OBS_DEPLOY.md](OBS_DEPLOY.md) · [obs/](obs/)
- Phase 5.2 security: [PHASE5_VPS_SECURITY.md](PHASE5_VPS_SECURITY.md)
- VPS2 platform hub (later): [VPS2_DEV_PLATFORM.md](VPS2_DEV_PLATFORM.md)
- Fleet Grafana interim (laptop): [GRAFANA_FLEET_DEV.md](GRAFANA_FLEET_DEV.md)
