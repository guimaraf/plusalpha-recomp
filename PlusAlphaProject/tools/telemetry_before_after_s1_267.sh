#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly OBSERVER_SH="$SCRIPT_DIR/observe_gameplay.sh"

exec "$OBSERVER_SH" "$@"
