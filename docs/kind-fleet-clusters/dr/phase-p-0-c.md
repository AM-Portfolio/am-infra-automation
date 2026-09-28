# DR — Phase P / 0 / C

Skill: `am-kind-fleet` `reference/phase-p-0-c.md` · tests `tests/phase-p-0-c.md`.  
Index: [DR_DEPLOY.md](../DR_DEPLOY.md) · Sizing: [SIZING.md](SIZING.md).

## Prereq

None for P. Phase 0 needs P green. Phase C needs P + 0 green.

## Implement

### P — connections

- [ ] Load `VPS/.env` IPs only (no secrets in chat/git) — `VPS_3_IP`.
- [ ] Laptop Docker + `~/.asrax` + `am ai status` OK.
- [ ] `am ai mcp-sync --ide cursor --host-launchers` when Cloudflare MCP needed.
- [ ] SSH key reaches `VPS_3_IP` (VPS3).
- [ ] SSH session to VPS3 OK (day-2 `am-ops` after Phase 5.1).
- [ ] Cloudflare MCP: zone `asrax.in` listable.
- [ ] Cloudflare MCP: tunnels listable — `asrax-dr-tunnel` present.
- [ ] Cloudflare MCP: R2 `asrax-disaster` listable.

### 0 — protect data

- [ ] R2 `disaster/latest/` has postgres / mongodb / redis objects.
- [ ] Confirm **no** influx dump required on R2.
- [ ] Do not mutate/delete R2 in this phase.
- [ ] Do not `kind delete` on VPS3 until Phase C confirmed.

### C — clean VPS3 (confirm first)

- [ ] Inventory: `kind get clusters` / leftover containers / `/data/am-state`.
- [ ] User confirm before any Kind delete.
- [ ] Record: Mem ~32 GB class; disk headroom; `nproc`.
- [ ] **Keep** `/data/am-state/terraform/dr/` — do not reset casually while prod is live.

## Test

- [ ] Laptop Docker OK.
- [ ] SSH VPS3 OK.
- [ ] Cloudflare MCP: zone + tunnels + R2 green.
- [ ] **Gate P / 0 / C** green.

## Grown

- [ ] P still green after 0/C.
- [ ] R2 disaster objects still present.

## Stop if fail / Refuse

Stay on P/0/C. No Phase 5 Kind prep until gates green. No auto-wipe tfstate. No CF/R2 mutate without confirm.
