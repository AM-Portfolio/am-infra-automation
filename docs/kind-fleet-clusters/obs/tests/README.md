# Obs thin test pointers

Domain lock: bare `grafana` / `loki` / `prometheus` / `tempo`.asrax.in.  
Host: VPS2 · runtime Docker Compose · **no Kind**.

| Phase | File | Gate |
|-------|------|------|
| P/0/C | [phase-p-0-c.md](phase-p-0-c.md) | SSH + host class 4c/8GB/200GB |
| 5.2 | [phase-5.md](phase-5.md) | `am-ops` key-only |
| 1 | [phase-1.md](phase-1.md) | data dirs + network `am-obs` |
| 2 | [phase-2.md](phase-2.md) | stack healthy; ports not public |
| 3 | [phase-3.md](phase-3.md) | CF cutover + MCP + multi-env ingest |
| 4 | [phase-4.md](phase-4.md) | interim retired |
| 6 | [phase-6-fleet.md](phase-6-fleet.md) | UIDs + boards + Alloy all envs + obs self-telemetry |
