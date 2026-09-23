#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="$GAME_ROOT/game.toml"
AUDIT_SCRIPT="$GAME_ROOT/../psxrecomp/tools/codegen_audit_game.py"
RECOMPILER_PATH="${1:-$GAME_ROOT/../psxrecomp/recompiler/build/psxrecomp-game}"

echo "======================================================================"
echo "        GERACAO DE FONTES - MICRO-LOTE S1-303                         "
echo "  Subsistema:  Sub-Cluster de Acao / Ataques Kairi (Tabela 0x801B3400) "
echo "  Orcamento:   6 funcoes novas, 271 palavras (1.084 bytes)            "
echo "  Meta:        1.311 funcoes nativas, 144.660 palavras (73,9631%)     "
echo "======================================================================"

cd "$GAME_ROOT"
"$RECOMPILER_PATH" --config "$CONFIG_PATH"
python3 "$AUDIT_SCRIPT" --config "$CONFIG_PATH"
