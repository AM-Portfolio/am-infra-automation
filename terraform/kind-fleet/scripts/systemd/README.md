# Contabo / Linux: install am-refresh-bridges timer

Auto-maps infra Endpoints (`am.io/bridge=cross-cluster`) from Docker DNS every 2 minutes so `apps-traefik-bridge` and `*-platform` stay current after Docker restarts.

Also install **`am-refresh-exposer-hostaliases`** so apps `hostAliases` track `am-port-exposer` Docker IP (store TCP :6379/:27017/:5432/:9092). Without it, pods may pin a stale Kind IP and CrashLoop on Mongo/Redis.

## One-time install (per host)

Assume checkout at `$HOME/am-repos/am-infra-automation` (edit paths if different).

```bash
REPO="${REPO:-$HOME/am-repos/am-infra-automation}"
UNIT_DIR="$HOME/.config/systemd/user"   # or /etc/systemd/system for root
mkdir -p "$UNIT_DIR"

# Copy units
cp "$REPO/terraform/kind-fleet/scripts/systemd/am-refresh-bridges.service" "$UNIT_DIR/"
cp "$REPO/terraform/kind-fleet/scripts/systemd/am-refresh-bridges.timer" "$UNIT_DIR/"

# Fix ExecStart path + ENV for this host (example: Contabo prod)
sed -i "s|/opt/am/am-infra-automation|$REPO|g" "$UNIT_DIR/am-refresh-bridges.service"
# ENV=prod | ENV=dr | ENV=preprod | ENV=dev
sed -i 's/^Environment=ENV=.*/Environment=ENV=prod/' "$UNIT_DIR/am-refresh-bridges.service"

# Ensure script is executable
chmod +x "$REPO/terraform/kind-fleet/scripts/refresh-cross-cluster-bridges.sh"
chmod +x "$REPO/terraform/kind-fleet/"*/scripts/refresh-cross-cluster-bridges.sh

# User systemd (linger so it survives logout)
systemctl --user daemon-reload
systemctl --user enable --now am-refresh-bridges.timer
loginctl enable-linger "$USER"   # once

# Verify
systemctl --user list-timers | grep am-refresh
systemctl --user start am-refresh-bridges.service
systemctl --user status am-refresh-bridges.service --no-pager
```

### Exposer hostAliases timer (same host)

```bash
cp "$REPO/terraform/kind-fleet/scripts/systemd/am-refresh-exposer-hostaliases.service" "$UNIT_DIR/"
cp "$REPO/terraform/kind-fleet/scripts/systemd/am-refresh-exposer-hostaliases.timer" "$UNIT_DIR/"
sed -i "s|/root/am-repos/am-infra-automation|$REPO|g" "$UNIT_DIR/am-refresh-exposer-hostaliases.service"
sed -i "s|ASRAX_HOME=.*|ASRAX_HOME=$HOME/.asrax|" "$UNIT_DIR/am-refresh-exposer-hostaliases.service"
chmod +x "$REPO/terraform/kind-fleet/scripts/refresh-exposer-hostaliases.sh"
systemctl --user daemon-reload
systemctl --user enable --now am-refresh-exposer-hostaliases.timer
```

For **root** units under `/etc/systemd/system`, replace `%h` with absolute paths and use `systemctl` (no `--user`). Set `ASRAX_HOME` to the operator home that holds `~/.asrax/kubeconfig.am-<env>-infra.yaml`.

## Manual one-shot (same as timer)

```bash
# Contabo prod
bash "$HOME/am-repos/am-infra-automation/terraform/kind-fleet/prod/scripts/refresh-cross-cluster-bridges.sh"
# or
ENV=prod bash "$HOME/am-repos/am-infra-automation/terraform/kind-fleet/scripts/refresh-cross-cluster-bridges.sh"
```

## DR / preprod

Same units; set `Environment=ENV=dr` or `ENV=preprod` in the service file (or use the matching thin wrapper as `ExecStart`).
