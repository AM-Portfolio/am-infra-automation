# GitNexus — Phase 4 (Hermes — optional)

Tests: [tests/phase-4.md](tests/phase-4.md).

## Prereq

Phase 3 green (`gitnexus.asrax.in` MCP works). RAM headroom per [SIZING.md](SIZING.md).

## Implement

- [x] Install Hermes (Docker): 2 CPU / 4 Gi; remote LiteLLM only (no Ollama).
- [x] MCP client → `https://gitnexus.asrax.in/api/mcp` (`hermes mcp test` → 17 tools).
- [x] Traefik + CF `hermes.asrax.in` → dashboard `:9119` (preprod tunnel).
- [x] Auth: Hermes dashboard basic auth (`am-ops`); API key gated; CF Access optional follow-up.
- [x] Skip `gitnexus-explorer` skill (team UI is gitnexus.asrax.in).

## Test

See [tests/phase-4.md](tests/phase-4.md).

## Grown

- [x] Hermes restart policy set; survives reboot (`--restart unless-stopped`).
- [x] UC-09 in [TEST_REPORT.md](TEST_REPORT.md).

## Refuse

- Local Ollama on 16 GB box alongside full GitNexus index Jobs.
- Unrestricted Vault/prod kube credentials in Hermes.
- Replacing qa-agent / support-agent with Hermes.
