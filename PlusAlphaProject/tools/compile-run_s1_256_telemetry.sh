#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-256-tele"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly EXPECTED_SHA=300F1B44336410C0F0DADAF746D2973D27ABCCF4EB391A36891D827DA67057C6

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

  bash tools/compile-run_s1_256_telemetry.sh

Configura e compila somente a build isolada S1-256 de telemetria. Nao abre o
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
        fail "Fontes S1-256 ausentes. Execute primeiro generate_s1_256_sources.ps1 no PowerShell."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_SHA" ]] ||
        fail "SHA-256 do manifesto nao corresponde ao S1-256 aprovado."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == 1055 ]] ||
        fail "A quantidade de funcoes geradas nao corresponde ao S1-256 esperado (1055)."

    require_range 'F 8018F10C'; require_range 'R 8018F10C 1D60'
    require_range 'F 8016FC28'; require_range 'R 8016FC28 9C'
    require_range 'F 801910A4'; require_range 'R 801910A4 234'
    require_range 'F 801914C0'; require_range 'R 801914C0 C8'
    require_range 'F 80191C84'; require_range 'R 80191C84 4A4'
    require_range 'F 80192D6C'; require_range 'R 80192D6C EC'
    require_range 'F 801930BC'; require_range 'R 801930BC 90'

    ! grep -Eq '^F (80103384|8017566C|8019E6D0|80192128|80193174|8019319C|801931C4|80192F60)$' "$RANGES_FILE" ||
        fail "Uma funcao fora da closure S1-256 apareceu nos fontes."
}

configure_and_build() {
    printf '\n==> Configurando S1-256 com telemetria e runtime estatico\n'
    cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR" -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DPSX_DEBUG_TOOLS=ON \
        -DPSX_STATIC_RUNTIME=ON
    printf '\n==> Compilando S1-256 de telemetria\n'
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

    require_symbol func_8018F10C
    require_symbol func_8016FC28
    require_symbol func_801910A4
    require_symbol func_801914C0
    require_symbol func_80191C84
    require_symbol func_80192D6C
    require_symbol func_801930BC
    ! nm -C "$EXE" |
        grep -q -E '[[:space:]]T[[:space:]]+func_(80103384|8017566C|8019E6D0|80192128|80193174|8019319C|801931C4|80192F60)$' ||
        fail "O executavel contem uma funcao fora da closure S1-256."

    printf '\n==> Runtime S1-256 validado; seis funcoes e 622 palavras presentes\n%s\n\nExecutavel: %s\nEste script nao abrira o jogo.\n' \
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
