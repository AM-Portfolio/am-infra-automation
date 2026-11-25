# AM obs hub — Docker Compose on VPS2

**SoT docs:** [docs/kind-fleet-clusters/OBS_DEPLOY.md](../../docs/kind-fleet-clusters/OBS_DEPLOY.md) · [obs/](../../docs/kind-fleet-clusters/obs/).

## Locked

- Host: VPS2 · **4c / 8 GB / ~200 GB** · **no Kind** · **no external DB**
- Data: `/data/am-state/obs/{loki,prometheus,tempo,grafana}/`
- Edge: Traefik + cloudflared (tunnel → Traefik only)
- Backends not published on the public NIC
- **Blackbox** (`blackbox` service):
  - `blackbox-prod-edge` — coarse edge (`am.asrax.in`, `/gateway`, `auth.asrax.in`)
  - `blackbox-prod-services` — **prod-only** per-service probes for `am-apps-prod` + `am-agents-prod` (405 / 5xx / connect-fail). Grafana module `prod-services-down` → Cliq with **service name**, namespace, and restart count.
- **Cliq relay** (`cliq-relay`): Grafana contact points `email-and-cliq` / `cliq-only` → Zoho Cliq for **prod** `severity=critical|high` (firing **and** resolved). Resolved cards include **service name** + **total resolved time** (startsAt→endsAt). Matcher `env=dev` stays Grafana-UI-only (no Cliq noise).
- **Users digest** (`users-digest`): daily **09:00 Asia/Kolkata** Cliq card — prod landed devices, new vs existing (7d lookback), sessions, logged-in users.

## Prereq on VPS2

```bash
mkdir -p /data/am-state/obs/{loki,prometheus,tempo,grafana,secrets,compose}
# copy this directory to /data/am-state/obs/compose/
cp -a . /data/am-state/obs/compose/
```

Secrets (never git):

- `/data/am-state/obs/secrets/cloudflared.token` — tunnel token
- `/data/am-state/obs/secrets/grafana.env` — `GF_AUTH_GENERIC_OAUTH_*` / admin bootstrap as needed
- `/data/am-state/obs/secrets/cliq-relay.env` — `ZOHO_CLIQ_WEBHOOK_URL` (prod alert channel; see `secrets/cliq-relay.env.example`)

## Run

```bash
cd /data/am-state/obs/compose
# Backends + Traefik (no tunnel yet)
docker compose up -d

# After placing /data/am-state/obs/secrets/cloudflared.token:
docker compose --profile tunnel up -d
docker compose ps
```

## Cutover

Do **not** move bare CNAMEs until Phase 2 tests green, tunnel profile up, and user confirms ([obs/phase-3.md](../../docs/kind-fleet-clusters/obs/phase-3.md)).

## Status (2026-09-25)

- Docker Engine on VPS2; stack on network `am-obs`.
- Tunnel: `asrax-obs-tunnel` · secret `/data/am-state/obs/secrets/cloudflared.env` (`TUNNEL_TOKEN=…`) · image `cloudflare/cloudflared:latest`.
- Bare CNAMEs → VPS2 tunnel; removed from `asrax-dev-tunnel`.
- Laptop interim Grafana/Loki/Prom scaled to 0.
- Start tunnel: `docker compose --profile tunnel up -d`