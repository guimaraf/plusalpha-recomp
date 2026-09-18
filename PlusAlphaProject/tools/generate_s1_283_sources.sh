#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="$GAME_ROOT/game.toml"
AUDIT_SCRIPT="$GAME_ROOT/../psxrecomp/tools/codegen_audit_game.py"
RECOMPILER_PATH="${1:-$GAME_ROOT/../psxrecomp/recompiler/build/psxrecomp-game}"

echo "======================================================================"
echo "        GERACAO DE FONTES - MICRO-LOTE S1-283                         "
echo "  Subsistema:  Core Combat & Action Engine (Blair & Zangief)           "
echo "  Orcamento:   3 funcoes novas, 924 palavras (3.696 bytes)            "
echo "  Meta:        1.205 funcoes nativas, 137.043 palavras (70,0686%)     "
echo "======================================================================"

cd "$GAME_ROOT"
"$RECOMPILER_PATH" --config "$CONFIG_PATH"
python3 "$AUDIT_SCRIPT" --config "$CONFIG_PATH"
