# Phase 2 tests — platform on infra

**Phase:** [../phase-2.md](../phase-2.md)

## Test

- [x] Argo / Temporal / Lago HTTPS OK
- [x] Tool pods on **infra** context
- [x] After soak: no live dependency on `kind-am-prod-platform`
- [x] `auth.asrax.in` green; one store stack

## Grown

- [x] Contabo Kind count = **2**

## Evidence

`kubectl` context = infra; deploy list (redact secrets). Clusters: `am-prod-infra` + `am-prod-apps`; `:6445` closed. 2026-09-26.
