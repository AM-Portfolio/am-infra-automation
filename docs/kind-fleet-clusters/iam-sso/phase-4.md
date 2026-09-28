# Phase 4 — SSO prove + rotate

**Goal:** Every major [CONSOLE_MATRIX.md](CONSOLE_MATRIX.md) row proved; shared kubeconfigs rotated; TODO Phase 10 owned items closed.

**Prereq:** Phase 3 Test + Grown green.

## Implement

- [x] Document rotate / invalidate previously shared admin kubeconfigs (laptop + VPS) — see below
- [x] CONSOLE_MATRIX majors listed with `phase_wired` + `test` column for operator ticks
- [x] Vault human path: Keycloak OIDC (`vault/oidc.tf`); no day-to-day root `VAULT_TOKEN`
- [x] Point [TODO.md Phase 10](../TODO.md#phase-10--sso-prove) to this pack
- [ ] Operator: rotate any kubeconfigs previously emailed; tick CONSOLE_MATRIX `test` after G26 prove

### Rotate procedure (operators)

1. On VPS: regenerate break-glass only — `scripts/shared/gen-kubeconfig.sh` (do **not** email).
2. Invalidate prior SA tokens: delete/recreate `am-admin` SA in `kube-system` or wait 24h token TTL.
3. Tell teammates: use Keycloak + Headlamp / oidc-login only.
4. Confirm no `client-key-data` in day-to-day onboarding docs.

## Test

Use [tests/phase-4.md](tests/phase-4.md).

## Grown

- [ ] Phases 1–3 still green
- [ ] Workload Vault CSI / kubernetes-apps auth still healthy
- [ ] G26 domain-only still clean

## Stop if fail

Do not disable break-glass until SSO prove is green.

## Refuse

- No committing rotated secrets
- No Authentik fallback
