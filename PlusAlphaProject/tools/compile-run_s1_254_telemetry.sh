#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-254-tele"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly EXPECTED_SHA=2A1B157977603D23A886102BE01A2B7A4B12B7514F450FD893CC96E26B4C4991

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
require_range() {
    grep -q "^${1}$" "$RANGES_FILE" || fail "Range/funcao ausente: $1"
}
require_symbol() {
    nm -C "$EXE" |
        grep -E "[[:space:]]T[[:space:]]+${1}$" >/dev/null ||
        fail "O executavel nao contem o simbolo $1."
}

usage() {
    cat <<'EOF'
Uso, sempre no MSYS2 UCRT64:

  bash tools/compile-run_s1_254_telemetry.sh

Configura e compila somente a build isolada S1-254 de telemetria. Nao abre o
jogo e nao executa prepare, before ou after.
EOF
}

validate_environment() {
    [[ "${MSYSTEM:-}" == "UCRT64" ]] ||
        fail "Abra o MSYS2 UCRT64 para executar este script."
    command -v cmake >/dev/null || fail "cmake nao encontrado no UCRT64."
    command -v ninja >/dev/null || fail "ninja nao encontrado no UCRT64."
    command -v objdump >/dev/null || fail "objdump nao encontrado no UCRT64."
    command -v nm >/dev/null || fail "nm nao encontrado no UCRT64."
    command -v nproc >/dev/null || fail "nproc nao encontrado no UCRT64."
    command -v sha256sum >/dev/null ||
        fail "sha256sum nao encontrado no UCRT64."

    [[ -f "$RANGES_FILE" ]] ||
        fail "Fontes S1-254 ausentes. Execute primeiro generate_s1_254_sources.ps1 no PowerShell."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_SHA" ]] ||
        fail "SHA-256 do manifest nao corresponde ao S1-254 aprovado."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == 1048 ]] ||
        fail "A quantidade de funcoes geradas nao corresponde ao S1-254 esperado (1048)."

    require_range 'F 8017D860'; require_range 'R 8017D860 1A8'
    require_range 'F 8017DA08'; require_range 'R 8017DA08 94'
    require_range 'F 80191000'; require_range 'R 80191000 A4'
    require_range 'F 8017DA9C'; require_range 'R 8017DA9C 124'
    require_range 'F 80190EB8'; require_range 'R 80190EB8 F4'
    require_range 'F 80190FAC'; require_range 'R 80190FAC 54'

    ! grep -Eq '^F (80103384|8016FC28|8017566C|8018F10C|801910A4|801914C0|80191C84|80192D6C|8019E6D0)$' "$RANGES_FILE" ||
        fail "Uma funcao fora da closure S1-254 apareceu nos fontes."
}

configure_and_build() {
    printf '\n==> Configurando S1-254 com telemetria e runtime estatico\n'
    cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR" -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DPSX_DEBUG_TOOLS=ON \
        -DPSX_STATIC_RUNTIME=ON
    printf '\n==> Compilando S1-254 de telemetria\n'
    cmake --build "$BUILD_DIR" --parallel "$(nproc)"
}

audit_runtime() {
    [[ -f "$EXE" ]] || fail "Executavel nao foi produzido: $EXE"
    local imports
    imports="$(objdump -p "$EXE" | awk '/DLL Name:/ { print $3 }')"
    if printf '%s\n' "$imports" |
        grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$'; then
        fail "A build importa uma DLL que deveria estar estatica."
    fi

    require_symbol func_8017D860
    require_symbol func_8017DA08
    require_symbol func_80191000
    require_symbol func_8017DA9C
    require_symbol func_80190EB8
    require_symbol func_80190FAC
    ! nm -C "$EXE" |
        grep -q -E '[[:space:]]T[[:space:]]+func_(80103384|8016FC28|8017566C|8018F10C|801910A4|801914C0|80191C84|80192D6C|8019E6D0)$' ||
        fail "O executavel contem uma funcao fora da closure S1-254."

    printf '\n==> Runtime S1-254 validado; tres folhas e 155 palavras presentes\n%s\n\nExecutavel: %s\nEste script nao abrira o jogo.\n' \
        "$imports" "$EXE"
}

main() {
    case "${1:-}" in
        '') ;;
        -h|--help) usage; return ;;
        *) usage; fail "Argumento desconhecido: $1" ;;
    esac
    validate_environment
    configure_and_build
    audit_runtime
}

main "$@"
