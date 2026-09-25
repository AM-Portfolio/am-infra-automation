# Zero-trust access layer

Cloudflare Access (multi-app) + Keycloak OTP + IP allowlist via GitHub workflow. Synced with [`kind-fleet-clusters/TODO.md`](kind-fleet-clusters/TODO.md) **Phase ZT**.

Identity / roles / Identity Admin UI: [`am-platform/docs/features/enterprise-identity-admin-rbac.md`](../../am-platform/docs/features/enterprise-identity-admin-rbac.md).

## Phase tracker

| Phase | Title | Status |
|-------|--------|--------|
| ZT-D0 | Docs pack | [x] This file + identity feature doc |
| ZT-P0 | MFA enroll (OTP optional; Access off) | [ ] Flags ready: `otp_optional_enroll=true`, `mfa_enforce=false`, `access_enforce=false` — ops must enroll TOTP on auth-dev |
| ZT-R | Role unify + create defaults | [x] Canonical roles + create_mode member/viewer |
| ZT-UI | Identity Admin console | [x] `am_identity_admin` package + `/admin` groups/custom-roles |
| ZT-IP | IP workflow + registry + data-plane | [x] workflow + registry.json + modules (apply pending) |
| ZT-EDGE | Access apps + Alloy Service Token | [x] modules wired; `access_enforce` still false until ZT-P1 |
| ZT-P1 | Enforce MFA + Access | [ ] Set `mfa_enforce` + `access_enforce` + Grafana/Argo local pw off |
| ZT-V | Verification smoke | [ ] |

Terraform flags (defaults **false** until ZT-P1):

- `mfa_enforce` — Keycloak browser flow requires OTP; human clients `directAccessGrantsEnabled=false`
- `access_enforce` — Cloudflare Access applications enabled

## ZT-P0 — Ops OTP enroll (before Access)

1. Confirm `kind-fleet/dev/platform`: `mfa_enforce=false`, `otp_optional_enroll=true`
2. Confirm `kind-fleet/dev/edge`: `access_enforce=false`
3. Open `https://auth-dev.asrax.in` → Account → configure TOTP (Authenticator app)
4. Repeat for every ops account that will use Grafana/Argo after ZT-P1
5. Only then set `mfa_enforce=true` and `access_enforce=true` in one window

## Access applications

| App key | Hosts | Roles | IP |
|---------|-------|-------|-----|
| `product-ui` | `am-dev.asrax.in` (UI) | user, viewer, ops, admin, super_admin | optional |
| `obs` | `grafana.asrax.in`, `loki.asrax.in`, `prometheus.asrax.in` (bare; all envs) | ops, admin, super_admin | workflow |
| `platform-ops` | argocd, vault UI, temporal, traefik | ops, admin, super_admin | workflow |
| `platform-tools` | n8n, openproject, lago, growthbook, litellm, langfuse, novu | ops, admin, super_admin | workflow |
| `store-uis` | pgadmin, mongo-express, redis-ui, kafka-ui, minio, influx | ops, admin, super_admin | **required** |
| `auth` | auth-dev | **No Access** | N/A |
| `data-plane` | (TCP only) | ops/admin CIDRs | registry |

**auth-dev:** never behind Access (IdP chicken-and-egg). Break-glass: separate CF email PIN policy for 1–2 ops emails.

## IP registration (GitHub workflow)

1. Ops runs [`.github/workflows/register-access-ip.yml`](../.github/workflows/register-access-ip.yml) (`workflow_dispatch`)
2. Inputs: `action` (add|remove), `cidr`, `apps` (comma-separated keys), `reason`, optional `expires`
3. PR updates [`terraform/kind-fleet/access-allowlist/registry.json`](../terraform/kind-fleet/access-allowlist/registry.json)
4. After merge: `terraform apply` on `kind-fleet/dev/edge` (and exposer ACL / data-plane module)

Built-in always allowed: Kind `172.19.0.0/16`, WG `10.77.1.0/24`.

**Who:** GitHub Environment `zero-trust-ip` — ops team only. End users / `user` role never self-serve.

## Alloy + Loki/Prometheus

When `access_enforce` enables Access on loki/prometheus, the **same apply** must:

1. Create Access Service Token
2. Write id/secret to Vault `apps/data/<env>/infra/cloudflare-access`
3. Wire Alloy `CF-Access-Client-Id` / `CF-Access-Client-Secret` headers
4. Enable Access apps for loki + prometheus

Module fails plan if obs Access is on without Alloy wiring.

## Acceptance (ZT-V)

| Test | Expect |
|------|--------|
| Open auth-dev, no Access cookie | Keycloak login (not CF interstitial) |
| Open grafana, no session, after ZT-P1 | CF Access challenge |
| Login as `user` → grafana | Access deny |
| Login as `user` → am-dev | Access allow |
| Password-grant on human OIDC client | 401 / unauthorized_client |
| Unregistered IP → postgres TCP | refused |
| Alloy → Loki/Prom after Access | push OK (Service Token) |

HTTP-testable ZT-V cases live in Postman collection **AM Zero-Trust** (workspace Asrax), run against shared env **AM - Dev**. Keep `zt_enforce_expected=false` while `access_enforce` / `mfa_enforce` are off (ZT-P0 must pass); set `zt_enforce_expected=true` after ZT-P1 to assert deny/challenge and Service Token allow. Not covered in Postman: CF browser interstitial UX, TCP data-plane IP refuse, Alloy DaemonSet push.

## Modules

- [`terraform/modules/core/zero-trust-access`](../terraform/modules/core/zero-trust-access)
- [`terraform/modules/core/data-plane-ip-allowlist`](../terraform/modules/core/data-plane-ip-allowlist)
- Wire: [`terraform/kind-fleet/dev/edge`](../terraform/kind-fleet/dev/edge)
