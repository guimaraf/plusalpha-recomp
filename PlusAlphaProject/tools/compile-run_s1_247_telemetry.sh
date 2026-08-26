#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-247-tele"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Uso, sempre no MSYS2 UCRT64:

  bash tools/compile-run_s1_247_telemetry.sh

Configura e compila a build isolada S1-247 de telemetria. Ao final, confere
o callback nativo 0x801A92B8, os registradores e as DLLs importadas. Este
script nao abre o jogo.
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
    [[ -f "$RANGES_FILE" ]] || fail "Ranges S1-247 ausentes: $RANGES_FILE"
    require_range "F 801A92B8"; require_range "R 801A92B8 E4"
    require_range "F 801A7CB4"; require_range "F 801A8E00"; require_range "F 801A8E50"; require_range "F 8019F464"
    require_range "F 8011D030"; require_range "F 8011D078"; require_range "F 8011D310"; require_range "F 80107A74"; require_range "F 80162D68"; require_range "F 80137FE8"; require_range "F 80138084"; require_range "F 8013827C"; require_range "F 801102A0"; require_range "F 8013CB08"
    ! grep -q '^F 8019E6D0$' "$RANGES_FILE" || fail "A funcao em quarentena 0x8019E6D0 apareceu nos fontes."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == "1034" ]] || fail "A quantidade de funcoes geradas nao corresponde ao S1-247 esperado (1034)."
}

configure_and_build() {
    printf '\n==> Configurando S1-247 com runtime estatico\n'
    cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DPSX_DEBUG_TOOLS=ON -DPSX_STATIC_RUNTIME=ON
    printf '\n==> Compilando S1-247 de telemetria\n'
    cmake --build "$BUILD_DIR" --parallel "$(nproc)"
}

audit_runtime() {
    [[ -f "$EXE" ]] || fail "Executavel nao foi produzido: $EXE"
    local imports
    imports="$(objdump -p "$EXE" | awk '/DLL Name:/ { print $3 }')"
    if printf '%s\n' "$imports" | grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$'; then fail "A build ainda importa uma DLL de runtime que deveria estar estatica."; fi
    require_symbol "func_801A92B8"; require_symbol "func_801A7CB4"; require_symbol "func_801A8E00"; require_symbol "func_801A8E50"; require_symbol "func_8019F464"
    require_symbol "func_8011D030"; require_symbol "func_8011D078"; require_symbol "func_8011D310"; require_symbol "func_80107A74"; require_symbol "func_80162D68"; require_symbol "func_80137FE8"; require_symbol "func_80138084"; require_symbol "func_8013827C"; require_symbol "func_801102A0"; require_symbol "func_8013CB08"
    ! nm -C "$EXE" | grep -q -E '[[:space:]]T[[:space:]]+func_8019E6D0$' || fail "O executavel contem o candidato em quarentena func_8019E6D0."
    printf '\n==> Runtime validado: S1-247 presente, callback rastreavel e runtime estatico\n%s\n\nExecutavel: %s\n' "$imports" "$EXE"
}

main() { case "${1:-}" in "") ;; -h|--help) usage; return ;; *) usage; fail "Argumento desconhecido: $1" ;; esac; validate_environment; configure_and_build; audit_runtime; }
main "$@"
