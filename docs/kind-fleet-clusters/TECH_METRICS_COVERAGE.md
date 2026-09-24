# Technical metrics coverage — fleet DEV (apps + agents)

**Goal:** Technical / Services Service dropdown lists every Ready app/agent with Prom `application` series.

**Service query:** `label_values({namespace="$namespace",application=~".+"}, application)`

## Snapshot before (2026-09-24)

| NS | Ready deploys | Had Prom `application` | Missing scrape annotations |
|----|---------------|------------------------|----------------------------|
| `am-apps-dev` | 21 | 8 | 11 |
| `am-agents-dev` | 10 | 5 | 3 |

### Missing scrape (enabled in this change)

**Apps:** am-api-gateway-dev, am-asrax-corp-dev, am-asrax-proxy-dev, am-asrax-ui-dev, am-email-extractor-dev, am-identity-dev, am-modern-ui-dev, am-notification-dev, am-oms-dev, am-subscription-dev, am-user-platform-dev  

**Agents:** am-ai-gateway, am-mkt-agents-dev, am-mkt-portal-ui-dev  

### Scraped but may lack Micrometer `application`

Alloy sets target label `application` from container name (strip `-dev`) so `up` and series without Micrometer `application` still fill the dropdown. River comments must use `//` (not `#`) or Alloy config reload fails.

## Verified after (2026-09-24)

| NS | Ready deploys | Prom `application` values | Every Ready deploy has `up{application=~".+"}` |
|----|---------------|---------------------------|-----------------------------------------------|
| `am-apps-dev` | 21 | 26 (≥21; extras = Micrometer aliases) | Yes (21/21) |
| `am-agents-dev` | 10 | 12 (≥10; extras = aliases/worker) | Yes (10/10) |

Spot-check: `am-identity`, `am-oms`, `am-fin-agent`, `am-ai-gateway` appear in `label_values` with scrape/`up` series (some `up=0` until path/port exports real metrics).

### Not in Technical apps/agents

Grafana, OpenProject, Lago, Langfuse — platform NS; use Platform boards / Explore.

## Fix (this change)

1. GitOps overlay `prometheus-scrape-*.yaml` + wire into Applications  
2. Alloy discovery: `application` from container name (`//` River comments)  
3. Live annotate Deployments for immediate scrape  

Logs: already in Loki via `service_name`; Alloy also sets log label `application` for Technical panels.
