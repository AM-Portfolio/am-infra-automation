# Obs — Phase P / 0 / C

Index: [OBS_DEPLOY.md](../OBS_DEPLOY.md) · Sizing: [SIZING.md](SIZING.md).  
Tests: [tests/phase-p-0-c.md](tests/phase-p-0-c.md).

## Prereq

None for P. Phase 0 needs P green. Phase C needs P + 0 green + **user confirm** before wipe.

## Implement

### P — connections

- [x] Load `VPS/.env` IPs only (no secrets in chat/git) — `VPS_2_IP`.
- [x] Laptop Docker + `~/.asrax` + `am ai status` OK when using MCP.
- [ ] `am ai mcp-sync --ide cursor --host-launchers` when Cloudflare MCP needed.
- [x] SSH key reaches `VPS_2_IP` (VPS2).
- [x] SSH session to VPS2 OK (day-2 `am-ops` after Phase 5.2).
- [ ] Cloudflare MCP: zone `asrax.in` listable.
- [ ] Cloudflare MCP: tunnels listable.

### 0 — protect data

- [x] Confirm interim hub still owns bare FQDNs on laptop until phase-3 ([GRAFANA_FLEET_DEV.md](../GRAFANA_FLEET_DEV.md)).
- [x] Do not mutate bare grafana/loki/prometheus/tempo CNAMEs in this phase.
- [x] Do not delete `/data/am-state` on VPS2.

### C — inventory / optional clean (confirm first)

- [x] Inventory: `docker ps` / `kind get clusters` (expect **no** Kind) / `/data/am-state`.
- [x] Record: Mem ~8 GB class; disk ~200 GB; `nproc` = 4.
- [x] User confirm before any volume wipe.
- [x] **Keep** `/data/am-state` layout; create obs dirs only in Phase 1.

## Test

- [x] SSH VPS2 as `am-ops` OK.
- [ ] Cloudflare MCP: zone + tunnels green.
- [x] Host class matches **4c / 8 GB / ~200 GB**.
- [x] **Gate P / 0 / C** green (CF MCP optional until phase-3).

## Grown

- [ ] P still green after 0/C.
- [ ] Interim laptop Grafana still answering until phase-3.

## Stop if fail / Refuse

- Kind create on VPS2.
- CF CNAME cutover in this phase.
- Wipe Loki data without confirm while any env is shipping logs.
