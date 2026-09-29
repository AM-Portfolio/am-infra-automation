#!/usr/bin/env bash
# Thin wrapper: kind fleet boot for env=dr
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$ROOT/scripts/kind-fleet-boot.sh" dr "$@"
