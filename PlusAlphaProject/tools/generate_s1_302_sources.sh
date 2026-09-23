#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="$GAME_ROOT/game.toml"
AUDIT_SCRIPT="$GAME_ROOT/../psxrecomp/tools/codegen_audit_game.py"
RECOMPILER_PATH="${1:-$GAME_ROOT/../psxrecomp/recompiler/build/psxrecomp-game}"

echo "======================================================================"
echo "        GERACAO DE FONTES - MICRO-LOTE S1-302                         "
echo "  Subsistema:  Pipeline de Armas/Props (Despachador e Variante ID 25) "
echo "  Orcamento:   2 funcoes novas, 330 palavras (1.320 bytes)            "
echo "  Meta:        1.305 funcoes nativas, 144.389 palavras (73,8245%)     "
echo "======================================================================"

cd "$GAME_ROOT"
"$RECOMPILER_PATH" --config "$CONFIG_PATH"
python3 "$AUDIT_SCRIPT" --config "$CONFIG_PATH"
