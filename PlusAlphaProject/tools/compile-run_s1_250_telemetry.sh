#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-250-tele"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Uso, sempre no MSYS2 UCRT64:

  bash tools/compile-run_s1_250_telemetry.sh

Configura e compila a build isolada S1-250 de telemetria. Ao final, confere
o invólucro 0x8019F5CC, seus tres auxiliares e as DLLs importadas.
Este script nao abre o jogo.
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
    [[ -f "$RANGES_FILE" ]] || fail "Ranges S1-250 ausentes: $RANGES_FILE"
    require_range "F 8019F5CC"; require_range "R 8019F5CC DC"
    require_range "F 8019FB4C"; require_range "R 8019FB4C C"
    require_range "F 8019FB84"; require_range "R 8019FB84 C"
    require_range "F 8019FB94"; require_range "R 8019FB94 3C"
    require_range "F 8019F6A8"; require_range "R 8019F6A8 1E8"
    require_range "F 8019FB64"; require_range "R 8019FB64 C"
    ! grep -q '^F 8019FBD0$' "$RANGES_FILE" || fail "A funcao 0x8019FBD0 apareceu fora da closure."
    ! grep -q '^F 8019E6D0$' "$RANGES_FILE" || fail "A funcao em quarentena 0x8019E6D0 apareceu nos fontes."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == "1041" ]] || fail "A quantidade de funcoes geradas nao corresponde ao S1-250 esperado (1041)."
}

configure_and_build() {
    printf '\n==> Configurando S1-250 com runtime estatico\n'
    cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DPSX_DEBUG_TOOLS=ON -DPSX_STATIC_RUNTIME=ON
    printf '\n==> Compilando S1-250 de telemetria\n'
    cmake --build "$BUILD_DIR" --parallel "$(nproc)"
}

audit_runtime() {
    [[ -f "$EXE" ]] || fail "Executavel nao foi produzido: $EXE"
    local imports
    imports="$(objdump -p "$EXE" | awk '/DLL Name:/ { print $3 }')"
    if printf '%s\n' "$imports" | grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$'; then fail "A build ainda importa uma DLL de runtime que deveria estar estatica."; fi
    require_symbol func_8019F5CC; require_symbol func_8019FB4C; require_symbol func_8019FB84; require_symbol func_8019FB94
    require_symbol func_8019F6A8; require_symbol func_8019FB64
    ! nm -C "$EXE" | grep -q -E '[[:space:]]T[[:space:]]+func_8019FBD0$' || fail "O executavel contem func_8019FBD0 fora da closure."
    ! nm -C "$EXE" | grep -q -E '[[:space:]]T[[:space:]]+func_8019E6D0$' || fail "O executavel contem o candidato em quarentena func_8019E6D0."
    printf '\n==> Runtime validado: familia S1-249/S1-250 completa e runtime estatico\n%s\n\nExecutavel: %s\n' "$imports" "$EXE"
}

main() { case "${1:-}" in "") ;; -h|--help) usage; return ;; *) usage; fail "Argumento desconhecido: $1" ;; esac; validate_environment; configure_and_build; audit_runtime; }
main "$@"
