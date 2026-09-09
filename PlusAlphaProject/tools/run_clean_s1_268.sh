#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-268"
readonly EXE_PATH="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly GAME_CONFIG="$PROJECT_ROOT/game.toml"
readonly CUE_PATH="$PROJECT_ROOT/disc-a/Street Fighter EX Plus Alpha (USA).cue"

fail() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

validate_env() {
    [[ "${MSYSTEM:-}" == "UCRT64" ]] ||
        printf 'AVISO: Recomendado executar no MSYS2 UCRT64. MSYSTEM=%s\n' "${MSYSTEM:-indefinido}" >&2

    [[ -f "$EXE_PATH" ]] || fail "Executavel limpo ausente: $EXE_PATH\nExecute primeiro: bash tools/build_clean_s1_268.sh"
    [[ -f "$GAME_CONFIG" ]] || fail "Arquivo de configuracao ausente: $GAME_CONFIG"
    [[ -f "$CUE_PATH" ]] || fail "Imagem CUE ausente: $CUE_PATH"
}

validate_env

printf '======================================================================\n'
printf '  INICIANDO STREET FIGHTER EX PLUS ALPHA - BUILD LIMPA S1-268         \n'
printf '  Perfil: RelWithDebInfo (Sem ferramentas de debug / 60 FPS limpo)    \n'
printf '======================================================================\n'

cd "$PROJECT_ROOT"
exec "$EXE_PATH" --game "$GAME_CONFIG" --disc "$CUE_PATH"
