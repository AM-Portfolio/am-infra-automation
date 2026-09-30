# GitNexus thin test pointers

Domain lock: bare `gitnexus.asrax.in` (+ optional `hermes.asrax.in`).  
Host: Contabo **nonprod** · runtime systemd serve `:4747` (phase 2).

| Phase | File | Gate |
|-------|------|------|
| 0 | [phase-0.md](phase-0.md) | Inventory recorded; confirm before scale |
| 1 | [phase-1.md](phase-1.md) | Four NS at 0; edge Ready; MemAvailable OK |
| 2 | [phase-2.md](phase-2.md) | `:4747/health`; am-platform indexed |
| 3 | [phase-3.md](phase-3.md) | Public health + MCP |
| 4 | [phase-4.md](phase-4.md) | Hermes HTTPS + MCP call (optional) |
| 5 | [phase-5.md](phase-5.md) | qa-agent URL + stub + TEST_REPORT |
