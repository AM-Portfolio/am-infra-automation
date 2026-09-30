# GitNexus — Phase 2 (Hub + serve + am-platform pilot)

Tests: [tests/phase-2.md](tests/phase-2.md).  
Hub: **`am-gitnexus`** · Bootstrap: `vps/bootstrap-gitnexus.sh` (update `HUB_ROOT=/opt/am/gitnexus`).

## Prereq

Phase 1 green (RAM free). Hub repo exists or extract completed.

## Implement

### 2a — Hub on disk

- [x] Hub repo **`am-gitnexus`** created/pushed (GitHub AM-Portfolio/am-gitnexus).
- [x] Local path `f:\am-repos\am-repos\am-gitnexus`; env `AM_GITNEXUS_HUB` via `scripts/run.ps1`.
- [x] Ladybug cap used for local serve: `GITNEXUS_LBUG_BUFFER_POOL_SIZE=2147483648`.
- [x] VPS `/opt/am/gitnexus` clone + systemd on Contabo (`vps-hts`, 2026-09-28).

### 2b — Pilot registration

- [x] `am-platform/.code-intelligence.yaml`: `group_path: platform/am-platform`.
- [x] `scan_roots` includes identity/subscription/notification/user-platform/mcp-hub/libraries.

### 2c — Index + serve

- [x] Indexed am-platform locally (2026-09-28, ~39s, 7029 nodes).
- [x] `group:sync` run from hub.
- [x] Local serve: `gitnexus serve --host 127.0.0.1 --port 4747` (running).
- [x] Contabo systemd unit `gitnexus-serve` active; host `:4747` → 200; am-platform 6357 nodes.
- [ ] FTS repair (`GITNEXUS_LBUG_EXTENSION_INSTALL=auto`) — still unavailable (load-only).

## Test

See [tests/phase-2.md](tests/phase-2.md).

## Grown

- [ ] Serve survives reboot (`systemctl enable`).
- [ ] Ladybug env persists in unit file.
- [ ] Pilot index present after restart.

## Refuse

- Running embeddings on every commit.
- Indexing inside the live serve process (use Job/CLI separately).
- Leaving hub under `am-scripts` as SoT.
