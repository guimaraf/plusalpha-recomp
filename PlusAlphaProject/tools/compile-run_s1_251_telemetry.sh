#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-251-tele"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Uso, sempre no MSYS2 UCRT64:

  bash tools/compile-run_s1_251_telemetry.sh

Configura e compila a build isolada S1-251 de telemetria. Este script nao
abre o jogo e nao executa a coleta BEFORE/AFTER.
EOF
}

require_range() { grep -q "^${1}$" "$RANGES_FILE" || fail "Range/funcao ausente: $1"; }
require_symbol() { nm -C "$EXE" | grep -E "[[:space:]]T[[:space:]]+${1}$" >/dev/null || fail "O executavel nao contem o simbolo $1."; }

validate_environment() {
    [[ "${MSYSTEM:-}" == "UCRT64" ]] || fail "Abra o MSYS2 UCRT64 para executar este script."
    command -v cmake >/dev/null || fail "cmake nao encontrado no UCRT64."
    command -v ninja >/dev/null || fail "ninja nao encontrado no UCRT64."
    command -v objdump >/dev/null || fail "objdump nao encontrado no UCRT64."
    command -v nm >/dev/null || fail "nm nao encontrado no UCRT64."
    command -v nproc >/dev/null || fail "nproc nao encontrado no UCRT64."
    [[ -f "$RANGES_FILE" ]] || fail "Fontes S1-251 ausentes. Execute primeiro generate_s1_251_sources.ps1 no PowerShell."
    require_range "F 8014C708"; require_range "R 8014C708 28"
    require_range "F 8019F5CC"; require_range "R 8019F5CC DC"
    require_range "F 8019F6A8"; require_range "R 8019F6A8 1E8"
    ! grep -Eq '^F (80103384|8016FC28|8017566C|8019E6D0)$' "$RANGES_FILE" || fail "Uma funcao fora do micro-lote apareceu nos fontes."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == "1042" ]] || fail "A quantidade de funcoes geradas nao corresponde ao S1-251 esperado (1042)."
}

configure_and_build() {
    printf '\n==> Configurando S1-251 com telemetria e runtime estatico\n'
    cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DPSX_DEBUG_TOOLS=ON -DPSX_STATIC_RUNTIME=ON
    printf '\n==> Compilando S1-251 de telemetria\n'
    cmake --build "$BUILD_DIR" --parallel "$(nproc)"
}

audit_runtime() {
    [[ -f "$EXE" ]] || fail "Executavel nao foi produzido: $EXE"
    local imports
    imports="$(objdump -p "$EXE" | awk '/DLL Name:/ { print $3 }')"
    if printf '%s\n' "$imports" | grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$'; then fail "A build importa uma DLL que deveria estar estatica."; fi
    require_symbol func_8014C708
    require_symbol func_8019F5CC
    require_symbol func_8019F6A8
    ! nm -C "$EXE" | grep -q -E '[[:space:]]T[[:space:]]+func_(80103384|8016FC28|8017566C|8019E6D0)$' || fail "O executavel contem uma funcao fora do micro-lote."
    printf '\n==> Runtime S1-251 validado; wrapper de 10 palavras presente\n%s\n\nExecutavel: %s\nEste script nao abrira o jogo.\n' "$imports" "$EXE"
}

main() {
    case "${1:-}" in
        "") ;;
        -h|--help) usage; return ;;
        *) usage; fail "Argumento desconhecido: $1" ;;
    esac
    validate_environment
    configure_and_build
    audit_runtime
}

main "$@"
