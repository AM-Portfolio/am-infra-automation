# GitNexus track â€” test report

**Track:** [README.md](README.md) Â· **UC matrix:** [TESTING.md](TESTING.md)  
**Started:** 2026-09-28 Â· **Host:** Contabo nonprod (`vps-hts` / `103.127.146.57`)

## Execution status (2026-09-28)

| Phase | Status | Notes |
|-------|--------|-------|
| 0 Inventory | **done** | Contabo API up; public was **530** (DNS â†’ down prod tunnel) |
| 1 Scale-to-0 | **done** | dig Kind + Contabo four NS â†’ **replicas=0**; NS kept |
| 2 Hub + serve + pilot | **done** | `/opt/am/gitnexus`; am-platform indexed; systemd `:4747`; FTS repaired |
| 3 Edge cutover | **done** | DNS â†’ preprod tunnel; IngressRoute; public **200** |
| 4 Hermes | **done** | Docker `hermes` (4g/2cpu); MCP â†’ gitnexus (17 tools); `hermes.asrax.in` **302** auth |
| 5 Consumers + Grown | **done** | qa-agent `GNX_MCP_URL` (dev+preprod); stub; TEST_REPORT |

### Hermes

- Image: `nousresearch/hermes-agent:latest`
- Data: `/opt/am/hermes` (config, `.env`, dashboard password)
- Ports (Kind bridge only): `172.18.0.1:9119` dashboard, `:8642` API
- Auth: dashboard basic auth user `am-ops` (password file on host); API key in `/opt/am/hermes/.api_server_key`
- MCP: `hermes mcp test gitnexus` â†’ Connected, **17 tools** (`list_repos` included)
- Model: OpenAI-compat via `https://litellm.munish.org/v1` (LiteLLM was **502** at cutover â€” chat may need LiteLLM healthy)
- Terminal backend: `docker` (sandboxed)
- Edge: CNAME + preprod tunnel + IngressRoute â†’ dashboard 9119

### Host GitNexus

- FTS: `analyze --repair-fts` on am-platform succeeded 2026-09-28
- Ladybug home: `/var/lib/gitnexus-lbug`

## UC results

| ID | Result | Notes |
|----|--------|-------|
| UC-01 | **pass** | Public gitnexus **200** |
| UC-02 | **pass** | Serve up |
| UC-03 | **pass** | am-platform indexed |
| UC-04 | **pass** | Edge left Running |
| UC-05 | **pass** | Scale-to-0 |
| UC-06 | **pass** | Ladybug env |
| UC-07 | ready | Cursor â†’ `https://gitnexus.asrax.in/api/mcp` |
| UC-08 | **pass** | values.dev + values.preprod `GNX_MCP_URL` |
| UC-09 | **pass** (extended) | Multi-MCP + Together; see Hermes multi-MCP section |

## Operator notes

1. Dashboard password: `cat /opt/am/hermes/.dashboard_password` on Contabo (user `am-ops`).
2. When LiteLLM recovers, chat works with existing `.env` key; else replace `OPENAI_API_KEY`.
3. Optional: Cloudflare Access app for `hermes.asrax.in` (basic auth already on).
4. Scale apps/agents back to 1 when product work resumes.

### Hermes multi-MCP + Together (2026-09-28 evening)

Hub: https://github.com/AM-Portfolio/am-hermes → Contabo `/opt/am/am-hermes`; runtime `/opt/am/hermes`.

| Check | Result |
|-------|--------|
| Model | **Together** `meta-llama/Llama-3.3-70B-Instruct-Turbo` (8B Turbo not serverless) |
| T1–T4 | **PASS** (Together 200, chat PONG, dashboard 302, GitNexus 17 tools) |
| T4a | **PASS** list_repos → am-platform |
| T4b | **PARTIAL** auth in am-identity `auth_router.py` |
| T4c | **PASS** route_map users/roles admin APIs |
| T4d | **PARTIAL** login context 5 callers |
| T4g | MCP bridge **PASS** (52 tools); dashboard search empty |
| T4argo | MCP bridge connects; `list_applications` **FAIL** HTTP 404 |
| WhatsApp | allowlist `919148752257` applied; **QR pair pending** (interactive TTY / dashboard) |
| Bridges | systemd `hermes-mcp-grafana` :18741 · `hermes-mcp-argocd` :18742 |
