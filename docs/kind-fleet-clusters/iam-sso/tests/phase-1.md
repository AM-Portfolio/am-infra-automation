# Tests — Phase 1 (Keycloak foundation)

G26/G27: domain only.

- [x] `https://auth.asrax.in/realms/am-realm/.well-known/openid-configuration` returns 200 (verified; issuer may show auth-dr behind CF LB)
- [ ] Realm session: SSO Session Max ≈ 86400s (Admin API or Keycloak MCP) — after re-apply configure_realm.py
- [ ] Access token from browser/password flow includes `am-ops` or `am-user` in `roles` and/or `groups`
- [ ] Clients present: `argocd`, `vault-ui`, `headlamp`, `kubectl`, `lago`, `langfuse`, `temporal-web`, `litellm`, `grafana`
- [x] No Authentik issuer in discovery
