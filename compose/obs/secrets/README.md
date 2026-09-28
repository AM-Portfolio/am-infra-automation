# Place real Cloudflare tunnel credentials on VPS2 (never commit):
#   /data/am-state/obs/secrets/cloudflared.env
# Contents:
#   TUNNEL_TOKEN=<token from Cloudflare GET .../cfd_tunnel/<id>/token>
#
# Tunnel name: asrax-obs-tunnel
# Ingress Host rules → http://traefik:80 for grafana / loki / prometheus / tempo.asrax.in
#
# Also keep a copy of the raw token at cloudflared.token if useful for rotation scripts.
