# IAM SSO — detailed testing plan

**SoT:** [CONSOLE_MATRIX.md](CONSOLE_MATRIX.md) · phase tests in [tests/](tests/)  
**Report:** [TEST_REPORT.md](TEST_REPORT.md)  
**Env order:** prod `*.asrax.in` first → dr → dev.

## Personas

| You say | Role | Expect |
|---------|------|--------|
| developer | `am-ops` | Ops consoles R/Y per matrix; not Keycloak Admin |
| viewer | `am-viewer` | Read-only where UI supports |
| user | `am-user` | modern-ui / gateway only |
| admin | `am-admin` | Majors + Keycloak Admin |

## Prereq — amctl Cursor MCP

```text
am ai status
am creds doctor
am ai sync
am ai mcp-sync --ide cursor --host-launchers
```

Reload Cursor MCP after sync. Smoke:

| MCP | Expect |
|-----|--------|
| Keycloak | Admin API against **fleet** issuer host; realm `am-realm` with roles `am-*` |
| Argo prod | `argocd_status` / `list_applications` read-only |
| Vault | list mounts or status (no day-to-day root narrative) |

If Keycloak MCP only sees `am-preprod-realm` / legacy `/auth`, retarget `KEYCLOAK_URL` + `KEYCLOAK_REALM=am-realm` in `~/.asrax/credentials.d/` to the fleet Keycloak (same host as OIDC discovery), then `am ai mcp-sync --ide cursor --host-launchers` again.

## Perf SLOs

| Check | SLO |
|-------|-----|
| OIDC discovery | under **2s** |
| Console landing (unauth) | under **5s** |
| Login redirect chain | under **8s** (when measured) |

## Use cases

Each UC records: HTTP, latency_ms, MCP client present, role result (`pass` / `fail` / `partial`).

| ID | Use case | Pass criteria |
|----|----------|---------------|
| UC-01 | Realm foundation | Discovery 200; no Authentik; roles `am-*`; all matrix clients; SSO ~86400s |
| UC-02 | Persona roles | Probe users have `am-ops` / `am-admin` / `am-user` |
| UC-03 | Keycloak Admin | `am-admin` only; `am-ops` denied |
| UC-04 | Argo CD | `am-ops` R; `am-admin` Y; `am-user` N + latency |
| UC-05 | Vault UI | OIDC; role matrix + latency |
| UC-06 | Headlamp | `am-ops` Y without shared kubeconfig |
| UC-07 | kubectl OIDC | `am-ops` get pods; not cluster-admin |
| UC-08 | Lago / Langfuse / Temporal / LiteLLM | Domain + login path for `am-ops` |
| UC-09 | Grafana / MinIO | `am-ops` Y; `am-user` N |
| UC-10 | Store UIs | kafka-ui, pgadmin, mongo-express, redis-ui, influx |
| UC-11 | Platform UIs | n8n, growthbook, openproject, novu, traefik |
| UC-12 | Product UI | modern-ui + gateway allow `am-user` |
| UC-13 | Perf summary | All domains vs SLOs; outliers flagged |

### Procedure (every surface)

1. `curl` HTTPS domain (G26 — no port-forward).
2. Record status + time_total (ms).
3. Keycloak MCP: client_id exists (when MCP points at `am-realm`).
4. Role checks: browser or token claim when passwords available; else mark **partial**.

## Refuse

- No localhost OIDC greens  
- No port-forward as Test green  
- No emailed kubeconfig as day-to-day pass  
- No inventing / committing secrets  

## After run

Update [TEST_REPORT.md](TEST_REPORT.md), tick [CONSOLE_MATRIX.md](CONSOLE_MATRIX.md) `test` column and [tests/](tests/) for proven rows only.
