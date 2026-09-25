# Prod — Phase 5.1 (VPS1 security before Kind)

Skill: `phase-5-vps.md` · tests `tests/phase-5.md` · Runbook: [PHASE5_VPS_SECURITY.md](../PHASE5_VPS_SECURITY.md).

## Prereq

Phase P + 0 (+ C as agreed) green. **No Kind / terraform Kind stacks on VPS1 until this gate green.**

## Implement

- [x] `scp scripts/vps-security/*` to VPS1 `/tmp/am-vps-security/` (CRLF stripped).
- [x] Root **once:** `bash /tmp/am-vps-security/install-phase51.sh` (re-run OK; user `am-ops` existed).
- [x] Day-2: SSH as **`am-ops@VPS_IP`** (key-only). Add local alias `am-vps1-ops` when convenient.
- [x] `am-ops`: no sudoers; password SSH disabled (sshd drop-in).
- [x] Install `am-ops-guard` wrappers at `/usr/local/bin/{kubectl,kind,terraform}`.
- [x] Install `break-glass-kind.sh` at `/usr/local/sbin/` (root-only G1).
- [x] Log `/var/log/am-break-glass.log` present.
- [x] `/data/am-state` writable by `am-ops`; root kubeconfig hardened `0400` when present.
- [x] `/data/am-state/terraform/prod/` created; `am-ops` can write.

## Test

### Shell

- [x] Reconnect as `am-ops` (`whoami=am-ops`).
- [x] `sudo true` fails / needs password (no sudoers) — OK.
- [x] `kubectl delete` refused (`am-ops-guard`).
- [x] `kind delete` / `terraform destroy` refused (`am-ops-guard`).
- [x] G1 script present for **root** (`/usr/local/sbin/break-glass-kind.sh`); log OK. (am-ops cannot exec G1 — expected.)

### Cloudflare MCP (read only)

- [x] Zone `asrax.in` listable.
- [x] Tunnels listable (incl. `asrax-prod-tunnel`).
- [x] R2 `asrax-disaster` listable.
- [x] No Contabo/preprod tunnel retarget this phase.

### Gate

- [x] **5.1 green** — ready for Phase 1 validate + later Phase 2 Kind on VPS1.

## Grown

- [x] Security still green; Phase 0 R2 still reachable from laptop.
- [x] Still no Kind create until Phase 1 + Phase 2 prereqs done.

## Notes (session)

- `terraform` real binary not on host yet — guard wrapper installed; install terraform before Phase 2 apply.
- Next: **Phase 1** ([phase-1.md](phase-1.md)) validate on checkout / VPS — no Kind create.

## Stop if fail / Refuse

Stay on Phase 5. Do not create Kind. Do not mutate CF DNS without confirm. Do not re-install unless broken.
