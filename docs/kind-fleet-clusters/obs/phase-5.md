# Obs — Phase 5.2 (VPS2 security)

Runbook: [PHASE5_VPS_SECURITY.md](../PHASE5_VPS_SECURITY.md).  
Index: [OBS_DEPLOY.md](../OBS_DEPLOY.md).  
Tests: [tests/phase-5.md](tests/phase-5.md).

## Prereq

Phase P + 0 (+ C as agreed) green. **No Kind / product stacks on VPS2.**

## Implement

### 5.2 — am-ops (VPS2)

- [x] Confirm Phase 5.2 already applied (historical TODO may show green).
- [x] Day-2: SSH as **`am-ops@VPS_2_IP`** (key-only). Alias `am-vps2-ops` when convenient.
- [x] `am-ops`: no sudoers; password SSH disabled.
- [x] `/data/am-state` writable by `am-ops`.
- [x] Docker Engine available to `am-ops` (docker group; Compose v2).
- [x] Still **no** Kind clusters on VPS2.

## Test

- [x] Reconnect as `am-ops` (`whoami=am-ops`).
- [x] `sudo true` fails / needs password.
- [x] Destructive Kind/kubectl wrappers refused if present (`am-ops-guard`).
- [x] **5.2 green** — ready for Phase 1.

## Grown

- [ ] Security still green.
- [ ] Still no Kind create for obs.

## Stop if fail / Refuse

- Kind create before Phase 1 Docker layout.
- Product apps on VPS2.
