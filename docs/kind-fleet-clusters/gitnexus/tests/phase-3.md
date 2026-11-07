# Test — GitNexus Phase 3

```bash
curl -sS -o /dev/null -w "%{http_code}\n" https://gitnexus.asrax.in/health
# Expect 200
# MCP: https://gitnexus.asrax.in/api/mcp — list_repos
```

- [ ] Public health **200**.
- [ ] MCP list_repos works from laptop.
- [ ] Latency within TESTING.md SLOs.
- [ ] UC-01 / UC-02 / UC-07 noted in TEST_REPORT.
