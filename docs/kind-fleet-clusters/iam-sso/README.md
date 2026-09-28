# IAM SSO — Keycloak pack

**Lead repo:** `am-infra-automation`  
**SoT checklists:** this folder (`phase-*.md` + `tests/`).  
**Parent:** [TODO.md Phase 10](../TODO.md#phase-10--sso-prove) · [PLAN.md](../PLAN.md) G24.

## Goal

One Keycloak (`am-realm`) login for all major operator surfaces. Teammates **do not** receive shared kubeconfigs.

| You say | Keycloak role |
|---------|---------------|
| user | `am-user` |
| developer | `am-ops` |
| viewer | `am-viewer` |
| admin | `am-admin` |

SSO session ≈ **24h**, then re-login. Console coverage: [CONSOLE_MATRIX.md](CONSOLE_MATRIX.md).

**Testing:** [TESTING.md](TESTING.md) (use-case catalog) · [TEST_REPORT.md](TEST_REPORT.md) (latest run).

## Loop

```text
Prereq → Implement → MCP sync → Test (this phase) → Test (grown)
```

G26/G27: domain-only proofs (`*.asrax.in`). No `localhost`, no `kubectl port-forward` for Test greens.

## Phases

| Phase | Doc | Test |
|-------|-----|------|
| 1 Keycloak foundation | [phase-1.md](phase-1.md) | [tests/phase-1.md](tests/phase-1.md) |
| 2 Major consoles OIDC | [phase-2.md](phase-2.md) | [tests/phase-2.md](tests/phase-2.md) |
| 3 Kube CLI OIDC | [phase-3.md](phase-3.md) | [tests/phase-3.md](tests/phase-3.md) |
| 4 Prove all + rotate | [phase-4.md](phase-4.md) | [tests/phase-4.md](tests/phase-4.md) |

## Teammate onboarding

1. Admin creates Keycloak user on `https://auth.asrax.in` → assign `am-ops` or `am-user`.
2. Open product / consoles on `*.asrax.in` → Keycloak password login.
3. Cluster UI: Headlamp (not emailed kubeconfig).
4. Cluster CLI (optional): `kubectl` + oidc-login against VPS API (see phase-3).
5. After ~24h session max → log in again.

**Never** email `~/.asrax/kubeconfig*.yaml` with `client-key-data` or shared SA tokens for day-to-day access. Break-glass only for operators (see phase-3).

## Credentials (VPS host SoT)

Per-env operator secrets live on the VPS that owns that env — **not in git**:

| Env | Host | Directory |
|-----|------|-----------|
| `prod` | Contabo VPS1 | `/data/am-state/credentials/prod/` |
| `dr` | VPS3 | `/data/am-state/credentials/dr/` |
| `dev` | laptop / VPS2 | `~/.asrax/credentials.d/` or `/data/am-state/credentials/dev/` |

Typical files: `keycloak-admin.env`, `infra-stores.env`, `oidc.env`, `sso-test-users.env`, `argocd-admin.env`, `vault-root.env`. Compat symlinks keep `prod-keycloak-admin.env` / `prod-infra-stores.env` working for older scripts.

Vault mirror: `apps/data/<env>/oidc/*` and `apps/data/<env>/infra/keycloak-test-users`.

Refresh on the owning host:

```bash
sudo bash scripts/kind-fleet/save-env-credentials.sh --env prod   # or dr|dev
```

That script migrates flat `*-keycloak-admin.env` / `*-infra-stores.env` into `<env>/`, writes `oidc.env` / `sso-test-users.env` / `argocd-admin.env` / `vault-root.env` from TF state + Vault when reachable, and keeps compat symlinks. Vault mirror (`apps/data/<env>/oidc/*`) needs a token with `apps` write ACL — host files remain authoritative if Vault returns 403.

Laptop dumps (gitignored): [VPS/credentials/README.md](../../../../VPS/credentials/README.md).

## Refuse

- No Authentik on fleet consoles
- No Vault `userpass` (Keycloak is the password IdP)
- No committing secrets / kubeconfigs
- No public laptop Kind API (`127.0.0.1` stays local-only)
