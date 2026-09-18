#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/buildTele-s1-283"

echo "=== Compilando buildTele-s1-283 ==="
cmake -B "$BUILD_DIR" -S "$PROJECT_ROOT" -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DPSX_DEBUG_TOOLS=ON \
    -DPSX_STATIC_RUNTIME=ON \
    -DPSX_LAUNCHER=ON

ninja -C "$BUILD_DIR"
echo "Build S1-283 concluida com sucesso."
