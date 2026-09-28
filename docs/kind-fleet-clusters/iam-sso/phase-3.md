# Phase 3 — Kube CLI OIDC (no shared kubeconfig)

**Goal:** Developers use kubectl via Keycloak OIDC; shared SA kubeconfig is **break-glass only**.

**Prereq:** Phase 2 Test green (Headlamp works without emailed kubeconfig).

## Implement

- [x] Kind/cluster TF: optional apiserver OIDC flags (`oidc-issuer-url`, `oidc-client-id=kubectl`, username/groups claims)
- [x] Runtime apiserver patch + ClusterRoleBindings (`oidc.tf` + `oidc-rbac.yaml`) for groups `am-ops` / `am-viewer` / `am-admin`
- [x] Document oidc-login stub kubeconfig (`kubeconfig.oidc.example.yaml` — no `client-key-data`)
- [x] Mark `cluster/access.tf` + `gen-kubeconfig.sh` as break-glass; do not use for teammate onboarding
- [x] prod infra + apps cluster modules pass `oidc_issuer_url=https://auth.asrax.in/realms/am-realm`
- [x] CONSOLE_MATRIX kubectl row `phase_wired` = 3
- [ ] Operator: re-apply infra/apps so apiserver OIDC + RBAC land on live Kind

## Test

Use [tests/phase-3.md](tests/phase-3.md).

## Grown

- [ ] Headlamp Phase 2 still works
- [ ] Break-glass SA still recoverable for operators

## Stop if fail

Keep existing admin.conf path for break-glass; do not wipe clusters.

## Refuse

- No emailing admin kubeconfigs as “developer access”
- No exposing laptop Kind API publicly
