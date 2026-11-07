# Test — GitNexus Phase 4 (Hermes)

```bash
curl -sS -o /dev/null -w "%{http_code}\n" https://hermes.asrax.in/
```

- [x] Hermes container running (4 Gi / 2 CPU); restart unless-stopped.
- [x] `hermes.asrax.in` reachable (HTTP **302** auth challenge / basic auth).
- [x] Hermes MCP → `gitnexus.asrax.in/api/mcp`; `list_repos` via `hermes mcp test` (17 tools).
- [x] UC-09 noted in TEST_REPORT.
