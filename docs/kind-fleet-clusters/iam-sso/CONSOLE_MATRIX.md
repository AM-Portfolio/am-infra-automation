# CONSOLE_MATRIX — IAM SSO SoT

Issuer: `https://auth.asrax.in/realms/am-realm` (dev: `auth-dev.asrax.in`).  
Role columns: `Y` = allowed, `N` = denied, `R` = read-only where UI supports.

`phase_wired`: `1` Keycloak client exists · `2` console OIDC wired · `3` kube CLI · `4` proved.

| Surface | client_id | domain (prod) | mode | am-user | am-ops | am-viewer | am-admin | phase_wired | test |
|---------|-----------|---------------|------|---------|--------|-----------|----------|-------------|------|
| Keycloak Admin | — | auth.asrax.in | IdP | N | N | N | Y | 1 | [ ] |
| Argo CD | argocd | argocd.asrax.in | native | N | R | R | Y | 2 | [ ] |
| Vault UI | vault-ui | vault.asrax.in | native | N | R | R | Y | 2 | [ ] |
| Headlamp (kube UI) | headlamp | headlamp.asrax.in | native | N | Y | R | Y | 2 | [ ] |
| kubectl (kube CLI) | kubectl | VPS API | OIDC | N | Y | R | Y | 3 | [ ] |
| Lago | lago | lago.asrax.in | native/proxy | N | Y | R | Y | 2 | [ ] |
| Langfuse | langfuse | langfuse.asrax.in | native/proxy | N | Y | R | Y | 2 | [ ] |
| Temporal Web | temporal-web | temporal.asrax.in | native/proxy | N | Y | R | Y | 2 | [ ] |
| LiteLLM | litellm | litellm.asrax.in | native/proxy | N | Y | R | Y | 2 | [ ] |
| modern-ui | am-modern-ui | am.asrax.in | native | Y | Y | Y | Y | 2 | [ ] |
| gateway | am-gateway | am.asrax.in | native | Y | Y | Y | Y | 2 | [ ] |
| Grafana | grafana | grafana.asrax.in | native | N | Y | R | Y | 2 | [ ] |
| MinIO | minio | minio.asrax.in | native | N | Y | R | Y | 2 | [ ] |
| Kafka UI | kafka-ui | kafka-ui.asrax.in | proxy | N | Y | R | Y | 2 | [ ] |
| pgAdmin | pgadmin | pgadmin.asrax.in | proxy | N | Y | R | Y | 2 | [ ] |
| Mongo Express | mongo-express | mongo-express.asrax.in | proxy | N | Y | R | Y | 2 | [ ] |
| Redis UI | redis-ui | redis-ui.asrax.in | proxy | N | Y | R | Y | 2 | [ ] |
| Influx UI | influx-ui | influx.asrax.in | proxy | N | Y | R | Y | 2 | [ ] |
| n8n | n8n | n8n.asrax.in | native/proxy | N | Y | R | Y | 2 | [ ] |
| GrowthBook | growthbook | growthbook.asrax.in | native/proxy | N | Y | R | Y | 2 | [ ] |
| OpenProject | openproject | openproject.asrax.in | native/proxy | N | Y | R | Y | 2 | [ ] |
| Novu | novu | novu.asrax.in | native/proxy | N | Y | R | Y | 2 | [ ] |
| Traefik dashboard | traefik | traefik.asrax.in | proxy | N | Y | R | Y | 2 | [ ] |

Non-prod domains use `*-dev.asrax.in` / `*-dr.asrax.in` (auth → `auth-dev` / `auth-dr`). Grafana fleet hub stays `grafana.asrax.in`.

Update `test` checkboxes in Phase 4 after domain proofs (G26).

**Apply order (prod):** platform (Keycloak + Headlamp + oauth2 proxies + Argo) → stores with `-var='oidc_client_secrets={...}'` from Vault `apps/data/prod/oidc/*` → infra/apps for apiserver OIDC.
