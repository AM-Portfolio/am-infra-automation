# DR — Phase ZT (access window)

Skill: `phase-zt.md` · tests `tests/phase-zt.md` · Detail: `docs/ZERO_TRUST_ACCESS.md`.

## Prereq

Phases 2–5 stand-up use open window. ZT-P0 after Phase 3. ZT-P1 later with fleet Phase 10.

## Implement

### Open window (during Phase 2–5)

- [ ] Keep `access_enforce=false`, `mfa_enforce=false` for DR Edge/ZT during stand-up.
- [ ] Do **not** put Access in front of `auth-dr.asrax.in`.

### ZT-P0 (after Keycloak up)

- [ ] Ops enroll TOTP on `https://auth-dr.asrax.in` while Access still off (or shared realm if SoT).
- [ ] Postman / flag `zt_enforce_expected=false` until P1.

### ZT-P1 (later)

- [ ] Same apply: `mfa_enforce` + `access_enforce` true — defer until enroll green + Phase 10.

## Test

- [ ] Ops reach Argo / Vault / store UIs **without** Access cookie during stand-up.
- [ ] `https://am-dr.asrax.in` login Tests work without Access.
- [ ] `auth-dr.asrax.in` not behind Access.

## Grown

- [ ] Access matrix matches intended window.
- [ ] Auth never wrapped.

## Stop if fail / Refuse

Do not enforce Access mid Phase 2–5. Do not Access-wrap `auth-dr.*`.
