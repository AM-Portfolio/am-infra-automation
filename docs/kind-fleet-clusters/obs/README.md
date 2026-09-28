# Obs track (VPS2)

Executable Implement + Test checkboxes for the **shared observability hub** (Docker Compose — no Kind).  
Index: [OBS_DEPLOY.md](../OBS_DEPLOY.md).  
**Sizing:** [SIZING.md](SIZING.md) · [OBS_VPS2_SIZING.md](../OBS_VPS2_SIZING.md).

## Host facts

- SSH day-2: `am-vps2-ops` (`am-ops`, key-only)
- **Hardware:** **4 vCPU · 8 GB RAM · ~200 GB SSD** — [SIZING.md](SIZING.md)
- IPs: `VPS/.env` — never commit passwords
- Runtime: **Docker Compose only — no Kind**
- Data: `/data/am-state/obs/{loki,prometheus,tempo,grafana}/`
- Tunnel: VPS2-owned → Traefik only
- UI: `https://grafana.asrax.in` · Logs: `https://loki.asrax.in` · Metrics: `https://prometheus.asrax.in` · Traces: `https://tempo.asrax.in`
- **Shared ingest:** all envs push here; label `environment` / `cluster`
- **No external DB** for Grafana/Loki — disk + SQLite only
- Product: none on this host · **no 11b** on 8 GB

## Confirm before clean

Inventory Docker containers / `/data/am-state/obs` → list → **user confirm** host → only then wipe volumes. Never auto-wipe live Loki chunks while prod/DR are shipping logs here.

## Phase map

| Phase | File | Tests |
|-------|------|-------|
| P / 0 / C | [phase-p-0-c.md](phase-p-0-c.md) | [tests/phase-p-0-c.md](tests/phase-p-0-c.md) |
| 5.2 VPS | [phase-5.md](phase-5.md) | [tests/phase-5.md](tests/phase-5.md) |
| 1 Docker | [phase-1.md](phase-1.md) | [tests/phase-1.md](tests/phase-1.md) |
| 2 Compose | [phase-2.md](phase-2.md) | [tests/phase-2.md](tests/phase-2.md) |
| 3 Cutover | [phase-3.md](phase-3.md) | [tests/phase-3.md](tests/phase-3.md) |
| 4 Retire | [phase-4.md](phase-4.md) | [tests/phase-4.md](tests/phase-4.md) |
| **6 Fleet ingest** | [phase-6-fleet.md](phase-6-fleet.md) | [tests/phase-6-fleet.md](tests/phase-6-fleet.md) |

## Loop

```text
Prereq → Implement → mcp-sync (when needed) → Test → Grown → next
```

Fail → stay on phase. Mark boxes here (not only in laptop TODO.md).
