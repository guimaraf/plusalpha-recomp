#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="$GAME_ROOT/game.toml"
AUDIT_SCRIPT="$GAME_ROOT/../psxrecomp/tools/codegen_audit_game.py"
RECOMPILER_PATH="${1:-$GAME_ROOT/../psxrecomp/recompiler/build/psxrecomp-game}"

echo "======================================================================"
echo "        GERACAO DE FONTES - MICRO-LOTE S1-279                         "
echo "  Subsistema:  Darun Combat, Lariats & Command Throw Dispatcher        "
echo "  Orcamento:   13 funcoes novas, 678 palavras (2.712 bytes)           "
echo "  Meta:        1.182 funcoes nativas, 134.596 palavras (68,8175%)     "
echo "======================================================================"

cd "$GAME_ROOT"
"$RECOMPILER_PATH" --config "$CONFIG_PATH"
python3 "$AUDIT_SCRIPT" --config "$CONFIG_PATH"
