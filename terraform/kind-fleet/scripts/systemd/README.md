# Contabo / Kind VPS: systemd units (root)

Install the **same three units** on every Kind VPS (`prod`, `dr`, `preprod`). Set `Environment=ENV=…` and checkout/`ASRAX_HOME` paths for that host.

| Unit | Purpose |
|------|---------|
| `am-refresh-bridges.timer` | Every 2m: cross-cluster Endpoints from Docker DNS |
| `am-refresh-exposer-hostaliases.timer` | Every 2m: apps CoreDNS `hosts` → current `am-port-exposer` IP (unit name kept; script is `refresh-exposer-coredns.sh`) |
| `am-kind-fleet-boot.timer` | Once after boot (~3m): ensure exposer → bridges → CoreDNS → smoke |

Do **not** install these on dig laptop Kind (`overlays/dev` refuses Contabo store pins).

**SoT:** app env uses DNS names only (`redis.asrax.in`, `temporal-rpc-<env>.asrax.in`). **Never** bake `172.18.x` into gitops hostAliases — CoreDNS hosts plugin is refreshed by the timer.

## One-time install (root, Contabo prod example)

```bash
REPO="${REPO:-/root/am-repos/am-infra-automation}"
UNIT_DIR=/etc/systemd/system
ENV_NAME=prod   # dr | preprod on other VPS
ASRAX_HOME=/home/am-ops/.asrax

cp "$REPO/terraform/kind-fleet/scripts/systemd/am-refresh-bridges.service" "$UNIT_DIR/"
cp "$REPO/terraform/kind-fleet/scripts/systemd/am-refresh-bridges.timer" "$UNIT_DIR/"
cp "$REPO/terraform/kind-fleet/scripts/systemd/am-refresh-exposer-hostaliases.service" "$UNIT_DIR/"
cp "$REPO/terraform/kind-fleet/scripts/systemd/am-refresh-exposer-hostaliases.timer" "$UNIT_DIR/"
cp "$REPO/terraform/kind-fleet/scripts/systemd/am-kind-fleet-boot.service" "$UNIT_DIR/"
cp "$REPO/terraform/kind-fleet/scripts/systemd/am-kind-fleet-boot.timer" "$UNIT_DIR/"

# Paths + ENV
for u in am-refresh-bridges.service am-refresh-exposer-hostaliases.service am-kind-fleet-boot.service; do
  sed -i "s|/opt/am/am-infra-automation|$REPO|g" "$UNIT_DIR/$u"
  sed -i "s|/root/am-repos/am-infra-automation|$REPO|g" "$UNIT_DIR/$u"
  sed -i "s|^Environment=ENV=.*|Environment=ENV=$ENV_NAME|" "$UNIT_DIR/$u"
  sed -i "s|^Environment=ASRAX_HOME=.*|Environment=ASRAX_HOME=$ASRAX_HOME|" "$UNIT_DIR/$u"
done

chmod +x \
  "$REPO/terraform/kind-fleet/scripts/refresh-cross-cluster-bridges.sh" \
  "$REPO/terraform/kind-fleet/scripts/refresh-exposer-coredns.sh" \
  "$REPO/terraform/kind-fleet/scripts/refresh-exposer-hostaliases.sh" \
  "$REPO/terraform/kind-fleet/scripts/ensure-port-exposer.sh" \
  "$REPO/terraform/kind-fleet/scripts/kind-fleet-boot.sh" \
  "$REPO/terraform/kind-fleet/$ENV_NAME/scripts/"*.sh 2>/dev/null || true

systemctl daemon-reload
systemctl enable --now am-refresh-bridges.timer
systemctl enable --now am-refresh-exposer-hostaliases.timer
systemctl enable --now am-kind-fleet-boot.timer

# Soft prove (no reboot)
systemctl start am-kind-fleet-boot.service
systemctl status am-kind-fleet-boot.service --no-pager
systemctl list-timers | grep am-
```

### DR / preprod

Same commands with `ENV_NAME=dr` or `ENV_NAME=preprod` on that VPS. Temporal RPC DNS:

- prod → `temporal-rpc-prod.asrax.in:7233` (UI `https://temporal.asrax.in`)
- dr → `temporal-rpc-dr.asrax.in:7233` (UI `https://temporal-dr.asrax.in`)
- preprod → `temporal-rpc-preprod.asrax.in:7233`

## Manual one-shot

```bash
bash "$REPO/terraform/kind-fleet/prod/scripts/kind-fleet-boot.sh"
# or
ENV=prod bash "$REPO/terraform/kind-fleet/scripts/kind-fleet-boot.sh"
```

## After VPS reboot (expected)

Within ~15 minutes: exposer ports `6379/27017/5432/9092/7233` OPEN, CoreDNS hosts IP matches exposer, bridges refreshed, market batch returns JSON (not SPA 405 HTML), support-worker Ready.
