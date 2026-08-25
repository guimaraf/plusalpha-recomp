#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-242"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"

fail() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Uso, sempre no MSYS2 UCRT64:

  bash tools/build_s1_242_checkpoint.sh

Configura e compila o checkpoint limpo S1-242 em diretorio proprio. A build
usa Release, PSX_DEBUG_TOOLS=OFF e runtime estatico: nao ha servidor TCP nem
instrumentacao de telemetria. O script valida os simbolos do checkpoint e as
DLLs importadas, mas nao abre nem fecha o jogo.
EOF
}

require_range() {
    local line="$1"
    grep -q "^${line}$" "$RANGES_FILE" || fail "Range/função ausente: $line"
}

validate_sources() {
    [[ "${MSYSTEM:-}" == "UCRT64" ]] ||
        fail "Abra o MSYS2 UCRT64 para executar este script."
    command -v cmake >/dev/null 2>&1 || fail "cmake nao encontrado no UCRT64."
    command -v ninja >/dev/null 2>&1 || fail "ninja nao encontrado no UCRT64."
    command -v objdump >/dev/null 2>&1 || fail "objdump nao encontrado no UCRT64."
    command -v nm >/dev/null 2>&1 || fail "nm nao encontrado no UCRT64."
    [[ -f "$RANGES_FILE" ]] || fail "Ranges S1-242 ausentes: $RANGES_FILE"

    require_range "F 80137FE8"
    require_range "R 80137FE8 9C"
    require_range "F 80138084"
    require_range "R 80138084 1F8"
    require_range "F 8013827C"
    require_range "R 8013827C 140"
    require_range "F 801102A0"
    require_range "F 8013CB08"
    ! grep -q '^F 8019E6D0$' "$RANGES_FILE" ||
        fail "A funcao em quarentena 0x8019E6D0 apareceu nos fontes."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == "1028" ]] ||
        fail "A quantidade de funcoes geradas nao corresponde ao S1-242 esperado (1028)."
}

configure_and_build() {
    printf '\n==> Configurando checkpoint limpo S1-242 (Release, sem telemetria)\n'
    cmake \
        -S "$PROJECT_ROOT" \
        -B "$BUILD_DIR" \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DPSX_DEBUG_TOOLS=OFF \
        -DPSX_STATIC_RUNTIME=ON

    printf '\n==> Compilando checkpoint limpo S1-242\n'
    cmake --build "$BUILD_DIR" --parallel "$(nproc)"
}

require_symbol() {
    local symbol="$1"
    nm -C "$EXE" | grep -E "[[:space:]]T[[:space:]]+${symbol}$" >/dev/null ||
        fail "O executavel nao contem o simbolo $symbol."
}

audit_runtime() {
    local imports
    local cache="$BUILD_DIR/CMakeCache.txt"
    [[ -f "$EXE" ]] || fail "Executavel nao foi produzido: $EXE"
    [[ -f "$cache" ]] || fail "Cache CMake ausente: $cache"
    grep -q '^CMAKE_BUILD_TYPE:STRING=Release$' "$cache" ||
        fail "O checkpoint nao esta configurado como Release."
    grep -q '^PSX_DEBUG_TOOLS:BOOL=OFF$' "$cache" ||
        fail "O checkpoint ainda possui PSX_DEBUG_TOOLS habilitado."
    grep -q '^PSX_STATIC_RUNTIME:BOOL=ON$' "$cache" ||
        fail "O checkpoint nao possui runtime estatico."

    imports="$(objdump -p "$EXE" | awk '/DLL Name:/ { print $3 }')"
    if printf '%s\n' "$imports" |
       grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$'; then
        printf '%s\n' "$imports" >&2
        fail "O checkpoint ainda importa uma DLL de runtime que deveria estar estatica."
    fi

    require_symbol "func_80137FE8"
    require_symbol "func_80138084"
    require_symbol "func_8013827C"
    require_symbol "func_801102A0"
    require_symbol "func_8013CB08"
    if nm -C "$EXE" | grep -E '[[:space:]]T[[:space:]]+func_8019E6D0$' >/dev/null; then
        fail "O executavel contem o candidato em quarentena func_8019E6D0."
    fi

    printf '\n==> Checkpoint limpo validado: Release, sem telemetria e runtime estatico\n'
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

    validate_sources
    configure_and_build
    audit_runtime
}

main "$@"
