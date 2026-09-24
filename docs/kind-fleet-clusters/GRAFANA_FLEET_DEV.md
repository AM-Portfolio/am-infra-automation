# Fleet Grafana — identity, MCP, publish, test (Phase 4h)

**UI:** `https://grafana.asrax.in` (bare FQDN — **one shared hub for all envs**).  
**Ingest:** `loki.asrax.in` / `prometheus.asrax.in` (never `*-dev` / `*-prod` / `*-dr` / `*-preprod`).  
Auth stays env-suffixed (`auth-dev.asrax.in`, …). Distinguishing sources = labels (`environment`, `cluster`), not hostname.

## Tunnel SoT (colocated with Grafana)

| Phase | Where Grafana runs | Who owns bare `grafana`/`loki`/`prometheus`.asrax.in |
|-------|--------------------|------------------------------------------------------|
| **Target (Phase 11)** | **VPS2** obs hub | **Only** the Cloudflare tunnel on **VPS2** (same host as Grafana). See [VPS2_DEV_PLATFORM.md](VPS2_DEV_PLATFORM.md). |
| **Interim (laptop Kind)** | `am-dev-platform` / `monitoring` | Laptop `asrax-dev-tunnel` on **infra** + Traefik bridges — temporary. Do **not** treat laptop as long-term owner of bare obs FQDNs. |

After Docker/Kind restart, refresh bridge Endpoints (Kind IPs drift):

```text
powershell -File terraform/kind-fleet/dev/obs/scripts/refresh-platform-bridges.ps1 -Env dev
```

Or run staged warmup (infra gates → batches of 5): `terraform apply` in `kind-fleet/dev/warmup` with a new `warmup_generation`.

NodePorts on platform node (Docker DNS `am-dev-platform-control-plane`): Grafana **30350**, Loki **30310**, Prometheus **30311**.

Pods = Terraform `kind-fleet/dev/obs` + Alloy on apps/infra/platform.  
Dashboards = **am-obs-platform** HTTP API (`targets/dev-fleet` or `targets/prod` → same `grafana.asrax.in`), never gitops ConfigMaps (ADR-010).  
GitOps am-logging in **every** env sets `LOKI_URL=https://loki.asrax.in/loki/api/v1/push`.

Sizing / Phase 11 VPS2: [OBS_VPS2_SIZING.md](OBS_VPS2_SIZING.md).

---

## One-page auto setup (next run)

| Step | Action | Done when |
|------|--------|-----------|
| 1 | `terraform apply` `kind-fleet/dev/{edge,obs}` — edge `bare_https_names` = grafana/loki/prometheus; obs `use_bare_fqdn` | Grafana/Loki/Prom Ready; bridges Host(`*.asrax.in`) |
| 2 | CF: CNAME `grafana` / `loki` / `prometheus` → **tunnel on the Grafana host** (laptop interim / **VPS2 target**) | Login + HTTPS push URLs resolve |
| 3 | `terraform apply` Alloy on apps + infra + platform — **HTTPS** bare Loki/Prom URLs | Alloy Ready; scrapes annotated pods → Prom |
| 4 | Folders + publish: create `am-platform` / `am-technical` / `am-product` / `am-support`, then `AM_OBS_ALLOW_LEGACY_PUBLISH=1 platform_ctl apply --target dev-fleet --unit artifacts --apply` | Search shows `tech-am-services`, `func-am-services`, platform-* |
| 5 | MCP identity: `pwsh -File scripts/setup-grafana-dev-mcp.ps1` | `~/.asrax/credentials.d/grafana-dev.env` has `GRAFANA_URL=https://grafana.asrax.in` |
| 6 | Cursor: MCP server **`grafana-dev`** → `~/.asrax/bin/grafana-dev-mcp.cmd`; reload | MCP `list_datasources` returns prometheus + loki |
| 7 | Identity (human): Keycloak client `grafana` → `https://grafana.asrax.in/*` (platform TF seeds bare host) | Login via Keycloak; break-glass admin in Vault `apps/data/dev/infra/observability` |

**Apply order:** `edge` → `obs` → `apps` → `infra` → platform Keycloak clients if redirect host changed. **Post-restart:** `exposer` → G25 vault CSI → `refresh-platform-bridges` / `warmup`.

**NodePorts (Kind bridge backends only):** Grafana **30350**, Loki gateway **30310**, Prometheus **30311**. Alloy egress uses HTTPS FQDNs.

| Alloy traffic | URL |
|---------------|-----|
| Loki push (apps/infra — **all envs**) | `https://loki.asrax.in/loki/api/v1/push` |
| Prom remote_write (apps/infra — **all envs**) | `https://prometheus.asrax.in/api/v1/write` |
| Same-cluster (platform Alloy) | ClusterIP `*.svc.cluster.local` (avoids CF hairpin) |
| am-logging (gitops) | same bare `LOKI_URL` in dev / preprod / prod / DR |

---

## MCP servers

| Cursor name | Target | Creds |
|-------------|--------|--------|
| **`grafana-dev`** | Fleet hub `https://grafana.asrax.in` | `credentials.d/grafana-dev.env` (SA token) |
| `grafana` | Legacy Contabo (if still configured) | `credentials.d/observability.env` |

Prefer **`grafana-dev`** MCP for fleet until VPS2 owns the hub permanently. Keep `AM_GRAFANA_MCP_WRITE=0` unless intentionally mutating.

---

## Test plan (MCP + UI)

### A — Integration / health

1. MCP `list_datasources` → UIDs `prometheus`, `loki` (exact — am-obs bindings).
2. MCP `check_datasources_health` on those UIDs → healthy.
3. MCP `search_dashboards` query `am-services` / `platform` → folders AM / Technical, AM / Platform, …

### B — Logs from services (LogQL)

Prefer MCP `query_loki_logs` datasourceUid=`loki`:

| Check | LogQL (last 30m) | Expect |
|-------|------------------|--------|
| Apps NS | `{cluster="am-dev-apps", namespace="am-apps-dev"}` | Lines from AM backends |
| Agents NS | `{cluster="am-dev-apps", namespace="am-agents-dev"}` | Agent pods |
| Infra | `{cluster="am-dev-infra"}` | Stores / Traefik / Vault |
| Platform | `{cluster="am-dev-platform", namespace="monitoring"}` | Grafana/Loki/Alloy |
| Env label | `{environment="dev"}` | Contract label present |

### C — Metrics / Technical Service dropdown

| Check | PromQL / UI | Expect |
|-------|-------------|--------|
| Apps applications | `label_values({namespace="am-apps-dev"}, application)` | Backend service names |
| Agents (if annotated) | `label_values({namespace="am-agents-dev"}, application)` | Agent apps with scrape annotations |
| Technical NS list | Namespace dropdown | `am-apps-*` + **`am-agents-dev`** (not infra/platform) |
| Platform NS list | AM / Platform boards | infra* + identity/vault/monitoring + **argocd/temporal/edge** |

Empty Service until Alloy remote_write has scraped at least once is OK for a minute; persistent empty after Ready Alloy = fail.

### D — Dashboards registered

| UID | Folder | Notes |
|-----|--------|-------|
| `tech-am-services` | AM / Technical | Service filled after Prom scrapes |
| `func-am-services` | AM / Technical | |
| `platform-overview` | AM / Platform | Infra/platform NS |
| `agents-work-summary` | AM / Support | |
| `obs-lab-platform-overview` | AM / Obs Lab | Lab isolation smoke |

MCP: `get_dashboard_by_uid` / `get_dashboard_summary` per UID.

### E — Identity

1. Open `https://grafana.asrax.in` → Keycloak `auth-dev.asrax.in` / `am-realm`.
2. `am-admin-test` (Vault `apps/data/dev/infra/keycloak-test-users`) → Admin path; break-glass admin only from Vault observability.
3. MCP uses **SA token**, not the human password.

### F — am-logging product events

GitOps `dev/apps/am-logging.yaml` sets `LOKI_URL=https://loki.asrax.in/loki/api/v1/push`. After Argo sync, product pushes should appear under a service label (confirm with LogQL once the app is synced).

---

## Ops lessons (smoother next apply)

- Do **not** reuse GrowthBook NodePort **30300** for Grafana.
- Disable Loki `chunksCache` / `resultsCache` / canary on Kind (memory).
- Alloy River maps need **commas** in `external_labels`.
- Alloy cross-cluster push is **HTTPS only** (`loki` / `prometheus`.asrax.in); never plain HTTP NodePort.
- Create Grafana **folders** before full `dev-fleet` publish (`folder not found` otherwise).
- Tunnel: DNS CNAME alone is not enough; tunnel **ingress** must list `grafana` / `loki` / `prometheus`.asrax.in.
- Stale `*-dev` CNAMEs can remain until cleaned; Traefik Host rules are bare only after this cutover.

---

## Related

- TODO Phase **4h**: [TODO.md](TODO.md)
- am-obs target: `am-obs-platform/targets/dev-fleet/`
- Setup script: [`scripts/setup-grafana-dev-mcp.ps1`](../../scripts/setup-grafana-dev-mcp.ps1)
