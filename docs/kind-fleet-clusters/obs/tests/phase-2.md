# Test — Obs Phase 2

- [ ] `docker compose ps` — Traefik, cloudflared, Grafana, Loki, Prometheus, Tempo healthy.
- [ ] From off-host: TCP to public IP `:3100` / `:9090` / `:3200` / `:3000` **refused** or filtered.
- [ ] Loki ready endpoint OK on Docker network.
- [ ] Grafana OIDC config present (SQLite under `/data/am-state/obs/grafana/`).
- [ ] No Postgres/Mongo containers required for this stack.
- [ ] Janitor service or cron defined (6h).
