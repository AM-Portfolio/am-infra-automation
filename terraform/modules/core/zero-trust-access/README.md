# zero-trust-access

Cloudflare Access multi-app module for AM kind-fleet.

- `access_enforce=false` (default): no Access apps (ZT-P0 enroll).
- `access_enforce=true`: creates Keycloak IdP, Access apps, Alloy Service Token.
- Never creates Access for `auth-dev`.
- Reads CIDRs from `terraform/kind-fleet/access-allowlist/registry.json`.

Wire from `kind-fleet/dev/edge`. See `docs/ZERO_TRUST_ACCESS.md`.
