#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly EXE_PATH="$PROJECT_ROOT/build-telemetry/StreetFighterEXPlusAlphaRecomp.exe"
readonly GAME_CONFIG="$PROJECT_ROOT/game.toml"
readonly CUE_PATH="$PROJECT_ROOT/disc-a/Street Fighter EX Plus Alpha (USA).cue"

fail() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

validate_env() {
    [[ "${MSYSTEM:-}" == "UCRT64" ]] ||
        printf 'AVISO: Recomendado executar no MSYS2 UCRT64. MSYSTEM=%s\n' "${MSYSTEM:-indefinido}" >&2

    [[ -f "$EXE_PATH" ]] || fail "Executavel de telemetria ausente: $EXE_PATH"
    [[ -f "$GAME_CONFIG" ]] || fail "Arquivo de configuracao ausente: $GAME_CONFIG"
    [[ -f "$CUE_PATH" ]] || fail "Imagem CUE ausente: $CUE_PATH"
}

validate_env

printf '[+] Iniciando Street Fighter EX Plus Alpha (Telemetria na porta 4531)...\n'
cd "$PROJECT_ROOT"
exec "$EXE_PATH" --game "$GAME_CONFIG" --disc "$CUE_PATH"
