#!/usr/bin/env bash
# Compat wrapper: store/Temporal DNS SoT is CoreDNS (not Deployment hostAliases).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
ENV_NAME="${1:-${ENV:-prod}}"
exec bash "$ROOT/refresh-exposer-coredns.sh" "$ENV_NAME"
