# DR — Phase 3 (platform / 3e)

Skill: `phase-3-platform.md` · tests `tests/phase-3.md`. Sizing: [SIZING.md](SIZING.md) — **`environment=dr`** on 32 GB.

## Prereq

Phase 2 Test + grown (2I) green. Access still **off**. Prod still serving on VPS1.

## Implement

### 3a — Identity

- [ ] Ensure `am-dr-platform` API **:6445** (G1/TF).
- [ ] `init-backend.ps1 -Env dr -Role platform` + apply Keycloak + Argo.
- [ ] Keycloak realm `am-realm`; roles admin/ops/viewer/user; **no Authentik**.
- [ ] Create **all** G24 OIDC clients; redirects `https://*-dr.asrax.in` only.
- [ ] Secrets → Vault; Argo `prune: false`; enroll infra API.
- [ ] Bridge `auth-dr.asrax.in` / `argocd-dr.asrax.in` on infra Traefik + DR tunnel.

### 3b / 3c / 3d

- [ ] Temporal on platform; PG via `postgres-dr.asrax.in` (not cross-cluster `*.svc`).
- [ ] Lago dedicated DB; P1 UIs as scoped (n8n, GrowthBook, …) on DR domains when enrolled.

## Test — 3e matrix

- [ ] `am ai sync` + `mcp-sync` when needed.
- [ ] Keycloak on `https://auth-dr.asrax.in` — realm readable.
- [ ] Admin + user OIDC password-grant (DR clients).
- [ ] Argo on `https://argocd-dr.asrax.in` (or shared Argo if SoT) — list apps; **am-dr-infra** enrolled.
- [ ] Phase 2 store domains still up (`*-dr`).
- [ ] Auth reachable **without** Access cookie.
- [ ] Grep fail: localhost / port-forward in OIDC redirects.

## Grown

- [ ] Replay 3e still green.
- [ ] Access/MFA still not enforced.
- [ ] Ready for **Phase 4 Vault** (not product pods yet).

## Stop if fail / Refuse

Stay on Phase 3. No Phase 4 Vault/Argo apps. No Authentik. No Access enforce mid Phase 3.
