#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly GAME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly CONFIG_PATH="$GAME_ROOT/game.toml"
readonly RECOMPILER="${RECOMPILER_PATH:-$GAME_ROOT/../psxrecomp/recompiler/build/psxrecomp-game.exe}"

if [[ ! -f "$RECOMPILER" ]]; then
    printf 'ERRO: psxrecomp-game nao encontrado em: %s\n' "$RECOMPILER" >&2
    exit 1
fi

printf '[+] Executando psxrecomp-game --config %s\n' "$CONFIG_PATH"
cd "$GAME_ROOT"
"$RECOMPILER" --config "$CONFIG_PATH"
printf '[+] Codigo gerado com sucesso em generated/\n'
