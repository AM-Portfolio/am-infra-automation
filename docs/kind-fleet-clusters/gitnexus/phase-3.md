# GitNexus — Phase 3 (Edge cutover)

Tests: [tests/phase-3.md](tests/phase-3.md).

## Prereq

Phase 2: localhost `:4747/health` green; am-platform indexed.

## Implement

- [x] Traefik IngressRoute + Service/Endpoints `infra/gitnexus` → host `172.18.0.1:4747` ([k8s/gitnexus-ingress.yaml](k8s/gitnexus-ingress.yaml)).
- [x] Cloudflare: CNAME → **asrax-preprod-tunnel**; tunnel ingress Host → Traefik.
- [x] Removed broken prod-tunnel DNS path (was 530; prod tunnel down).
- [x] Smoke from laptop: `https://gitnexus.asrax.in/` → **200**.
- [x] MCP mount: `https://gitnexus.asrax.in/api/mcp` (server logs confirm).

## Test

See [tests/phase-3.md](tests/phase-3.md).

## Grown

- [x] UC-01 / UC-02 recorded in [TEST_REPORT.md](TEST_REPORT.md).
- [x] TEAM-MCP docs in `am-gitnexus` still cite public URL (no change needed for Cursor).

## Refuse

- Exposing serve without Traefik / tunnel (raw public NodePort).
- Cutting DNS before local health green.
