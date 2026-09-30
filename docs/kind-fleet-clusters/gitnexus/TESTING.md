# GitNexus track — testing plan

**SoT gates:** [tests/](tests/) · **Report:** [TEST_REPORT.md](TEST_REPORT.md)  
**Loop:** Prereq → Implement → Test → Grown (fail → stay on phase).

## Personas

| You say | Role | Expect |
|---------|------|--------|
| ops | `am-ops` | Scale, bootstrap, CF/Traefik, serve health |
| developer | Cursor MCP | `gitnexus.asrax.in/api/mcp` query one repo at a time |
| qa | qa-agent | Await index; `GNX_MCP_URL`; degraded OK if empty |

## Use cases

| ID | Use case | Pass criteria |
|----|----------|---------------|
| UC-01 | Public health | `GET https://gitnexus.asrax.in/health` 200 |
| UC-02 | MCP HTTP | `POST …/api/mcp` tools/list or list_repos succeeds |
| UC-03 | Pilot index | `am-platform` in list_repos; route_map `/auth/login` non-empty |
| UC-04 | Edge kept | Traefik / cloudflared Ready after scale-to-0 |
| UC-05 | Scale-to-0 | Four apps/agents NS deploy replicas = 0 |
| UC-06 | Ladybug cap | Env `GITNEXUS_LBUG_BUFFER_POOL_SIZE` set on serve |
| UC-07 | Cursor TEAM-MCP | Laptop MCP points at public URL (not localhost) |
| UC-08 | qa-agent | `GNX_MCP_URL=https://gitnexus.asrax.in` after phase 5 |
| UC-09 | Hermes (opt) | `hermes.asrax.in` up; can call list_repos via MCP |

## Perf SLOs

| Check | SLO |
|-------|-----|
| `/health` | under **2s** |
| MCP list_repos | under **5s** |
| route_map pilot | under **15s** |

Record results in [TEST_REPORT.md](TEST_REPORT.md).
