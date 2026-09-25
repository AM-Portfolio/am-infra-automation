# Prod track (VPS1)

Executable Implement + Test checkboxes for **production Kind** stand-up.  
Index: [PROD_DEPLOY.md](../PROD_DEPLOY.md).  
**Sizing + Kind nodes:** [SIZING.md](SIZING.md) (current 8c/64GB · target shrink 6c/36GB).  
Skill narrative: `amctl/.../am-kind-fleet/reference/` + `reference/tests/` + `reference/sizing.md`.

## Host facts

- SSH day-2: `am-vps1-ops` (`am-ops`, key-only)
- **Current hardware:** **8 vCPU · 64 GB RAM · 500 GB SSD** — **serve first** on this class
- **Later:** obs offload frees room; optional shrink **6c / 36 GB** only after prod green — [SIZING.md](SIZING.md)
- IPs: `VPS/.env` — never commit passwords
- Credentials: `~/.asrax/credentials.d/prod.env` — **domain URLs only**
- Tunnel: `asrax-prod-tunnel` → Traefik only
- App UI: `https://am.asrax.in` · Auth: `https://auth.asrax.in` (bare prod names)
- Kind: infra **`two`** · apps/platform **`one`** · names `am-prod-{infra,apps,platform}`
- Pod sizing: TF `environment=prod` (full tables on 64 GB)

## Confirm before clean

Inventory Kind / volumes / `/data/am-state` → list → **user confirm** host + names → only then delete. Never auto-wipe prod tfstate.

## Skill map

| Phase | Skill implement | Skill tests |
|-------|-----------------|-------------|
| P/0/C | `phase-p-0-c.md` | `tests/phase-p-0-c.md` |
| 5 | `phase-5-vps.md` | `tests/phase-5.md` |
| 1 | `phase-1-tf.md` | `tests/phase-1.md` |
| 2 | `phase-2-infra.md` | `tests/phase-2.md` (2A–2I) |
| 3 | `phase-3-platform.md` | `tests/phase-3.md` |
| 4 | `phase-4-apps.md` | `tests/phase-4.md` |
| ZT | `phase-zt.md` | `tests/phase-zt.md` |
| Sizing | [SIZING.md](SIZING.md) + skill `reference/sizing.md` | `docs/kind-fleet-resources/SIZING.md` |

## Loop

```text
Prereq → Implement → mcp-sync (when needed) → Test → Grown → next
```

Fail → stay on phase. Mark boxes here (not only in laptop TODO.md).
