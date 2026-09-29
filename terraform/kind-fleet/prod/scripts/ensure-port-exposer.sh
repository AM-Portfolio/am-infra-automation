#!/usr/bin/env bash
# Thin wrapper: ensure port exposer for env=prod
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$ROOT/scripts/ensure-port-exposer.sh" prod "$@"
