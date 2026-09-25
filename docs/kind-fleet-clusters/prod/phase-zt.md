# Prod — Phase ZT (access window)

Skill: `phase-zt.md` · tests `tests/phase-zt.md` · Detail: `docs/ZERO_TRUST_ACCESS.md`.

## Prereq

Phases 2–4 stand-up use open window. ZT-P0 after Phase 3a/3e. ZT-P1 **not** required to declare prod writer green — do with/before fleet Phase 10.

## Implement

### Open window (during Phase 2–4)

- [ ] Keep `access_enforce=false`, `mfa_enforce=false` for prod Edge/ZT modules during stand-up.
- [ ] Do **not** put Access in front of `auth.asrax.in`.

### ZT-P0 (after Keycloak up)

- [ ] Every ops account enrolls TOTP on `https://auth.asrax.in` while Access still off.
- [ ] Postman / flag `zt_enforce_expected=false` until P1.

### ZT-P1 (later — one apply)

- [ ] Plan: `mfa_enforce` + `access_enforce` true in **same** apply.
- [ ] Alloy CF Access Service Token in **same** apply.
- [ ] Grafana/Argo local passwords off (OIDC).
- [ ] Defer until enroll green + Phase 10 timing.

## Test

### During stand-up / ZT-P0

- [ ] Ops reach Argo / Vault / Grafana / MinIO / store UIs **without** Access cookie.
- [ ] `https://am.asrax.in` login Tests work without Access.
- [ ] `auth.asrax.in` not behind Access.
- [ ] TOTP enroll complete for ops accounts.

### After ZT-P1 (when executed)

- [ ] Protected consoles challenge without Access cookie.
- [ ] Session + OTP opens consoles for enrolled ops.
- [ ] `auth.asrax.in` still open.
- [ ] Alloy still pushes; app login/token/quote still pass on domain.
- [ ] `zt_enforce_expected=true`.

## Grown

- [ ] Access matrix matches intended window (open vs enforce).
- [ ] Auth never wrapped.

## Stop if fail / Refuse

Do not enforce Access mid Phase 2–4. Do not skip ZT-P0 before P1. Do not Access-wrap `auth.*`.
