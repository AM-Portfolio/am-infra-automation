# Tests — Phase 2 (major consoles)

G26/G27: open via `https://*.asrax.in` only. No port-forward.

As **`am-ops`** (one Keycloak login):

- [ ] Argo CD UI accepts login
- [ ] Vault UI accepts login
- [ ] Headlamp accepts login
- [ ] Lago accepts login
- [ ] Langfuse accepts login
- [ ] Temporal Web accepts login
- [ ] LiteLLM UI accepts login
- [ ] Grafana accepts login
- [ ] MinIO console accepts login (if in scope for env)

As **`am-user`**:

- [ ] Denied Grafana / Headlamp / Argo / Vault (or policy matches CONSOLE_MATRIX)
- [ ] Product modern-ui still allowed

Grown:

- [ ] Phase 1 discovery + role claims still true
- [ ] Redirect URIs are domain-only (no localhost for fleet consoles)
