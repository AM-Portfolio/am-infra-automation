# Test — GitNexus Phase 2

```bash
curl -sS http://127.0.0.1:4747/health
# MCP / CLI: list_repos includes am-platform
# route_map or query for am-platform auth/login non-empty
```

- [ ] `/opt/am/gitnexus` present (am-gitnexus checkout).
- [ ] `GITNEXUS_LBUG_BUFFER_POOL_SIZE=2147483648` on serve unit/env.
- [ ] `curl http://127.0.0.1:4747/health` OK.
- [ ] `am-platform` indexed; group_path `platform/am-platform`.
- [ ] UC-03 / UC-06 noted in TEST_REPORT.
