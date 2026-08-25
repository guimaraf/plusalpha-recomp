#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-240-tele"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"

fail() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Uso, sempre no MSYS2 UCRT64:

  bash tools/build_s1_240_telemetry.sh

Configura e compila a build S1-240 de telemetria com SDL2, libgcc, libstdc++
e winpthread estaticos. Ao final, audita as DLLs importadas pelo executavel.
EOF
}

validate_environment() {
    [[ "${MSYSTEM:-}" == "UCRT64" ]] ||
        fail "Abra o MSYS2 UCRT64 para executar este script."
    command -v cmake >/dev/null 2>&1 || fail "cmake nao encontrado no UCRT64."
    command -v ninja >/dev/null 2>&1 || fail "ninja nao encontrado no UCRT64."
    command -v objdump >/dev/null 2>&1 || fail "objdump nao encontrado no UCRT64."
    command -v nm >/dev/null 2>&1 || fail "nm nao encontrado no UCRT64."
    [[ -f "$RANGES_FILE" ]] || fail "Ranges S1-240 ausentes: $RANGES_FILE"
    grep -q '^F 8013CB08$' "$RANGES_FILE" ||
        fail "A funcao 0x8013CB08 nao aparece nos fontes. Gere o S1-240 primeiro."
    grep -q '^R 8013CB08 84$' "$RANGES_FILE" ||
        fail "O range 0x8013CB08+0x84 nao aparece nos fontes S1-240."
    ! grep -q '^F 8019E6D0$' "$RANGES_FILE" ||
        fail "A funcao em quarentena 0x8019E6D0 ainda aparece nos fontes."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == "1024" ]] ||
        fail "A quantidade de funcoes geradas nao corresponde ao S1-240 esperado (1024)."
}

configure_and_build() {
    printf '\n==> Configurando S1-240 com runtime estatico\n'
    cmake \
        -S "$PROJECT_ROOT" \
        -B "$BUILD_DIR" \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DPSX_DEBUG_TOOLS=ON \
        -DPSX_STATIC_RUNTIME=ON

    printf '\n==> Compilando S1-240 de telemetria\n'
    cmake --build "$BUILD_DIR" --parallel "$(nproc)"
}

audit_runtime_imports() {
    local imports
    [[ -f "$EXE" ]] || fail "Executavel nao foi produzido: $EXE"

    imports="$(objdump -p "$EXE" | awk '/DLL Name:/ { print $3 }')"
    if printf '%s\n' "$imports" |
       grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$'; then
        printf '%s\n' "$imports" >&2
        fail "A build ainda importa uma DLL de runtime que deveria estar estatica."
    fi

    nm -C "$EXE" | grep -E '[[:space:]]T[[:space:]]+func_8013CB08$' >/dev/null ||
        fail "O executavel nao contem o simbolo compilado func_8013CB08."
    if nm -C "$EXE" | grep -E '[[:space:]]T[[:space:]]+func_8019E6D0$' >/dev/null; then
        fail "O executavel ainda contem o candidato em quarentena func_8019E6D0."
    fi

    printf '\n==> Runtime validado: candidato novo presente, candidato antigo ausente e nenhuma DLL nao-sistema obrigatoria\n'
    printf '%s\n' "$imports"
    printf '\nExecutavel: %s\n' "$EXE"
}

main() {
    case "${1:-}" in
        "") ;;
        -h|--help)
            usage
            return
            ;;
        *)
            usage
            fail "Argumento desconhecido: $1"
            ;;
    esac

    validate_environment
    configure_and_build
    audit_runtime_imports
}

main "$@"
