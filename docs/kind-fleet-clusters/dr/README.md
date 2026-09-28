# DR track (VPS3)

Executable Implement + Test checkboxes for **disaster-recovery Kind** stand-up.  
Index: [DR_DEPLOY.md](../DR_DEPLOY.md).  
**Sizing + Kind nodes:** [SIZING.md](SIZING.md) (8c/32GB · all one-node).  
Skill narrative: `amctl/.../am-kind-fleet/reference/` + `reference/tests/` + `reference/sizing.md`.

## Host facts

- SSH day-2: `am-vps3-ops` (`am-ops`, key-only)
- **Hardware:** **8 vCPU · 32 GB RAM · 500 GB SSD** — [SIZING.md](SIZING.md)
- IPs: `VPS/.env` — never commit passwords
- Credentials: `~/.asrax/credentials.d/dr.env` — **domain URLs only**
- Tunnel: `asrax-dr-tunnel` → Traefik only
- App UI: `https://am-dr.asrax.in` · Auth: `https://auth-dr.asrax.in`
- Kind: **all `one`** · names `am-dr-{infra,apps,platform}`
- Pod sizing: TF `environment=dr`
- WireGuard: VPS1 `10.77.1.1` ↔ VPS3 `10.77.1.2` (G20)

## Confirm before clean

Inventory Kind / volumes / `/data/am-state` → list → **user confirm** host + names → only then delete. Never auto-wipe DR tfstate while prod is live.

## Skill map

| Phase | Skill implement | Skill tests |
|-------|-----------------|-------------|
| P/0/C | `phase-p-0-c.md` | `tests/phase-p-0-c.md` |
| 5.1 / 5.3 | `phase-5-vps.md` | `tests/phase-5.md` |
| 1 | `phase-1-tf.md` | `tests/phase-1.md` |
| 2 | `phase-2-infra.md` | `tests/phase-2.md` (2A–2I) |
| 3 | `phase-3-platform.md` | `tests/phase-3.md` |
| **4 Vault** | `phase-4-apps.md` (vault/G25 only) | `tests/phase-4.md` |
| **5 Argo** | `phase-4-apps.md` (waves) | `tests/phase-4.md` + [phase-5-argo.md](phase-5-argo.md) |
| 6 G20/LB | `phase-6-12.md` | `tests/phase-6-12.md` |
| ZT | `phase-zt.md` | `tests/phase-zt.md` |
| Sizing | [SIZING.md](SIZING.md) + skill `reference/sizing.md` | `docs/kind-fleet-resources/SIZING.md` |

## Loop

```text
Prereq → Implement → mcp-sync (when needed) → Test → Grown → next
```

Fail → stay on phase. Mark boxes here (not only in laptop TODO.md).
