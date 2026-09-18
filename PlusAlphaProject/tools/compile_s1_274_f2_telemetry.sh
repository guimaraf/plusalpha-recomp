#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly BUILD_DIR="$PROJECT_ROOT/buildTele-s1-274-f2"
readonly TARGET_EXE="$BUILD_DIR/exPlusAlpha.exe"

fail() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

validate_env() {
    [[ "${MSYSTEM:-}" == "UCRT64" ]] ||
        printf 'AVISO: Recomendado executar no MSYS2 UCRT64. MSYSTEM=%s\n' "${MSYSTEM:-indefinido}" >&2

    if ! command -v cmake >/dev/null 2>&1; then
        fail "cmake nao encontrado no PATH."
    fi
}

validate_env

printf '======================================================================\n'
printf '     COMPILACAO DA BUILD DE TELEMETRIA - MICRO-LOTE S1-274 (F2)       \n'
printf '  Alvo: buildTele-s1-274-f2                                           \n'
printf '  Perfil: RelWithDebInfo (-O2 -g -DNDEBUG)                            \n'
printf '  Ferramentas de Debug: PSX_DEBUG_TOOLS=ON                            \n'
printf '======================================================================\n'

cd "$PROJECT_ROOT"

if [[ ! -d "$BUILD_DIR" ]]; then
    printf '[+] Configurando novo diretorio de buildTele-s1-274-f2...\n'
    cmake -B "$BUILD_DIR" -S "$PROJECT_ROOT" -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DPSX_DEBUG_TOOLS=ON \
        -DPSX_STATIC_RUNTIME=ON \
        -DPSX_LAUNCHER=ON
fi

printf '[+] Compilando target psx-runtime...\n'
cmake --build "$BUILD_DIR" --target psx-runtime

if [[ -f "$TARGET_EXE" ]]; then
    printf '\n[+] BUILD DE TELEMETRIA S1-274 (F2) CONCLUIDA COM SUCESSO!\n'
    printf '    Executavel pronto em: %s\n' "$TARGET_EXE"
else
    fail "O executavel nao foi produzido em: $TARGET_EXE"
fi
