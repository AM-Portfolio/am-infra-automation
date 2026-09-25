# Prod — Phase P / 0 / C

Skill: `am-kind-fleet` `reference/phase-p-0-c.md` · tests `tests/phase-p-0-c.md`.  
Index: [PROD_DEPLOY.md](../PROD_DEPLOY.md) · Sizing: [SIZING.md](SIZING.md) → take **prod** rows from [`kind-fleet-resources/SIZING.md`](../../kind-fleet-resources/SIZING.md).

## Prereq

None for P. Phase 0 needs P green. Phase C needs P + 0 green.

## Implement

### P — connections

- [x] Load `VPS/.env` IPs only (no secrets in chat/git).
- [x] Laptop Docker + `~/.asrax` + `am ai status` OK (operator machine) — Docker Server 29.2.1; `~/.asrax` present.
- [ ] `am ai mcp-sync --ide cursor --host-launchers` when Cloudflare MCP needed (MCP already usable this session).
- [x] SSH key reaches `VPS_IP` (VPS1).
- [x] SSH session to VPS1 OK — host `asrax` as `root` (day-2 `am-ops` after Phase 5).
- [x] Cloudflare MCP: zone `asrax.in` listable.
- [x] Cloudflare MCP: tunnels listable — `asrax-prod-tunnel` present (**status: down** until Phase 2 edge).
- [x] Cloudflare MCP: R2 `asrax-disaster` listable.

### 0 — protect data

- [x] R2 `disaster/latest/` has **postgres** objects (`postgres/shared|kind|…` sql.gz + BACKUP_OK).
- [x] R2 has **mongodb** objects (`mongodb/prod|shared` archives + BACKUP_OK).
- [x] R2 has **redis** objects (`redis/prod|shared|kind` dump.rdb + BACKUP_OK).
- [x] Confirm **no** influx dump required on R2 — only `influx/shared/.keep` placeholders.
- [x] Do not mutate/delete R2 in this phase.
- [x] Do not `kind delete` on VPS1 until Phase C confirmed.

### C — clean VPS1 (confirm first)

- [x] Inventory: `kind get clusters` → **No kind clusters found**; leftover: `am-cloudflared` container only; `/data/am-state/terraform/prod` **missing** (greenfield OK).
- [x] Already empty Kind — **no delete** needed (user confirm not required for no-op).
- [x] Record: Mem ~61–64 GB available class; disk `/` 512G ~20G used; `nproc`=16 logical CPUs on host.
- [x] **Keep** future `/data/am-state/terraform/prod/` — create in Phase 5/1, do not reset casually.

## Test

- [x] Laptop Docker `docker info` OK (Server 29.2.1).
- [x] SSH VPS1 OK.
- [x] Cloudflare MCP: zone + tunnels + R2 green.
- [x] **Gate P:** connections green — no Kind create yet.
- [x] R2 `disaster/latest` PG/Mongo/Redis listable — **Gate 0**.
- [x] Kind empty / clean state as agreed — **Gate C**.

## Grown

- [x] P still green after 0/C.
- [x] R2 disaster objects still present (clean did not wipe R2).

## Notes (2026-09-24/25 session)

- **Prod tunnel down** — expected until Phase 2 Traefik + cloudflared; do not block Phase 5/1.
- Sizing for later apply: **`environment=prod`** (not dev defaults) — [SIZING.md](SIZING.md).
- Next: **Phase 5.1** ([phase-5.md](phase-5.md)) before any Kind create.

## Stop if fail / Refuse

Stay on P/0/C. No Phase 5 Kind prep until gates green. No auto-wipe tfstate. No CF/R2 mutate without confirm.
