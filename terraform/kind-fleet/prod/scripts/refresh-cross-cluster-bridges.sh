#!/usr/bin/env bash
# Thin wrapper: refresh cross-cluster bridges for env=prod
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$ROOT/scripts/refresh-cross-cluster-bridges.sh" prod "$@"
