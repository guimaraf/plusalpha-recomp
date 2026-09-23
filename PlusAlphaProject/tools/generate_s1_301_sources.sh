#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="$GAME_ROOT/game.toml"
AUDIT_SCRIPT="$GAME_ROOT/../psxrecomp/tools/codegen_audit_game.py"
RECOMPILER_PATH="${1:-$GAME_ROOT/../psxrecomp/recompiler/build/psxrecomp-game}"

echo "======================================================================"
echo "        GERACAO DE FONTES - MICRO-LOTE S1-301                         "
echo "  Subsistema:  Pipeline de Armas/Props (Renderizador 3D da Adaga)     "
echo "  Orcamento:   1 funcao nova, 266 palavras (1.064 bytes)              "
echo "  Meta:        1.303 funcoes nativas, 144.059 palavras (73,6558%)     "
echo "======================================================================"

cd "$GAME_ROOT"
"$RECOMPILER_PATH" --config "$CONFIG_PATH"
python3 "$AUDIT_SCRIPT" --config "$CONFIG_PATH"
