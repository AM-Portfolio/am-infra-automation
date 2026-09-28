# DR — Phase 5.1 / 5.3 (VPS3 security + WireGuard)

Skill: `phase-5-vps.md` · tests `tests/phase-5.md` · Runbook: [PHASE5_VPS_SECURITY.md](../PHASE5_VPS_SECURITY.md).

**Note:** This file is **VPS security** (runs *before* Phase 1). Product **Argo** is [phase-5-argo.md](phase-5-argo.md) (after Phase 4 Vault).

## Prereq

Phase P + 0 (+ C as agreed) green. **No Kind / terraform Kind stacks on VPS3 until 5.1 green.**

## Implement

### 5.1 — am-ops

- [x] `scp scripts/vps-security/*` to VPS3 `/tmp/am-vps-security/` (CRLF stripped).
- [x] Root **once:** `bash /tmp/am-vps-security/install-phase51.sh`.
- [x] Day-2: SSH as **`am-ops@VPS_3_IP`** (key-only). Alias `am-vps3-ops` when convenient.
- [x] `am-ops`: no sudoers; password SSH disabled.
- [x] Install `am-ops-guard` wrappers; `break-glass-kind.sh` (include **promote / rs.stepUp**).
- [x] `/data/am-state` writable by `am-ops`; `/data/am-state/terraform/dr/` exists.

### 5.3 — WireGuard (VPS1 ↔ VPS3)

- [ ] Install WG on VPS1 + VPS3 (`install-wireguard-vps1-vps3.sh`).
- [ ] Peers: VPS1 `10.77.1.1` ↔ VPS3 `10.77.1.2` UDP 51820.
- [ ] Ping both ways over WG.

## Test

- [x] Reconnect as `am-ops` (`whoami=am-ops`).
- [x] `sudo true` fails / needs password.
- [x] `kubectl delete` / `kind delete` / `terraform destroy` refused (`am-ops-guard`).
- [x] G1 present for root; log OK.
- [x] WG ping VPS1↔VPS3 OK.
- [x] **5.1 + 5.3 green** — ready for Phase 1.

## Grown

- [ ] Security still green; Phase 0 R2 still reachable.
- [ ] Still no Kind create until Phase 1 + Phase 2 prereqs done (or inventory existing Kind).

## Stop if fail / Refuse

Stay on Phase 5.1/5.3. Do not create Kind until green. Do not mutate CF DNS without confirm.
