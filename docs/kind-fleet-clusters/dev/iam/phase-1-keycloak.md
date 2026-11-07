# IAM-1-DEV — Keycloak groups (humans)

## Prereq

IAM-0 Grown.

## Keycloak SoT (locked)

- **One live Keycloak:** Contabo prod `auth.asrax.in` / realm `am-realm`
- **DR Keycloak:** backup only — do not create dig-only groups there first
- Dig Contabo apps SSO against the **same** prod issuer (no `auth-dev` plane)

Realm roles appear in the token `groups` claim via `am-groups-from-roles` mapper (Keycloak module).

## Group / role model (`am-realm`)

**Teams:** `team-platform`, `team-data`, `team-apps`

**Access:**

- `access-grafana-viewer` / `access-grafana-editor` / `access-grafana-admin`
- `access-minio-read` / `access-minio-write`
- `access-kafka-ui`
- `access-bytebase-user` / `access-bytebase-dba`

SoT defaults: `terraform/modules/apps/keycloak/variables.tf` → `realm_roles` (applied on Contabo platform Keycloak).

## Implement

- [x] Roles listed in Keycloak module `realm_roles` (incl. access-* / team-*)
- [x] Grafana role attribute path maps `access-grafana-*` (+ legacy `am-admin` / `am-ops`)
- [x] OIDC client id `bytebase` added
- [ ] Re-apply Contabo platform Keycloak (or Admin API) so roles exist on live `am-realm`
- [ ] MinIO OpenID claim `groups` → policies for `access-minio-*`
- [ ] kafka-ui behind oauth2-proxy allowed_groups=`access-kafka-ui` (or am-ops)
- [ ] Matrix below kept current

### Group → role matrix

| Keycloak role | Grafana | MinIO | kafka-ui | Bytebase |
|---------------|---------|-------|----------|----------|
| access-grafana-viewer | Viewer | — | — | — |
| access-grafana-editor | Editor | — | — | — |
| access-grafana-admin | Admin | — | — | — |
| access-minio-read | — | read | — | — |
| access-minio-write | — | readwrite | — | — |
| access-kafka-ui | — | — | allow | — |
| access-bytebase-user | — | — | — | user |
| access-bytebase-dba | — | — | — | dba |

## Grown

- [ ] Tests in [tests/phase-1.md](tests/phase-1.md) green against **prod** Keycloak
