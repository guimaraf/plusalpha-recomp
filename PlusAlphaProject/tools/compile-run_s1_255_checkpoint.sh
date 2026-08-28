#!/usr/bin/env bash
# Checkpoint limpo cumulativo S1-255: Release sem telemetria.
# Este script somente configura, compila e audita o artefato. Nunca abre o jogo.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-255"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly AUDIT_SCRIPT="$FRAMEWORK_ROOT/tools/codegen_audit_game.py"
readonly EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly EXPECTED_RANGES_SHA256=30bcd2340878a0c9057ca4b8a66f582a0695af844b1e45e9409678951d76d404
readonly EXPECTED_FUNCTIONS=1049
readonly EXPECTED_MAIN_SHA256=1a932f2cf286930a967cf4ef03595b487480b84887f6630f5d3b57472401d8b0
readonly EXPECTED_CDROM_C_SHA256=2af1a59a2c18e0ebb47ec3fd614aaefeacd82fb0042440fbcd03652c18f4e845
readonly EXPECTED_CDROM_H_SHA256=75ccd4e0d03d6a407af55e6852cb9346b55233fb96b3a662dc0f15a8bf0b9186
readonly EXPECTED_DEBUG_SERVER_SHA256=40c2bd97e242ca6048227ba02e6af4327259bdb28f9c65969c2c72faea1f50d6

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
require_range() {
    grep -qxF "$1" "$RANGES_FILE" || fail "Range/funcao ausente: $1"
}
require_symbol() {
    nm -C "$EXE" |
        grep -Eq "[[:space:]]T[[:space:]]+$1$" ||
        fail "Simbolo emitido ausente no executavel: $1"
}
require_sha256() {
    local path="$1" expected="$2" actual
    [[ -f "$path" ]] || fail "Arquivo protegido ausente: $path"
    actual="$(sha256sum "$path" | awk '{print tolower($1)}')"
    [[ "$actual" == "$expected" ]] ||
        fail "SHA-256 inesperado em $path: $actual"
}

usage() {
    cat <<'EOF'
Uso, sempre no MSYS2 UCRT64:

  bash tools/compile-run_s1_255_checkpoint.sh

Gera o checkpoint limpo cumulativo S1-255 em Release, com
PSX_DEBUG_TOOLS=OFF e runtime estatico. O script nao gera fontes, nao
regenera a BIOS e nao abre ou fecha o jogo.
EOF
}

validate_sources() {
    [[ -f "$PROJECT_ROOT/CMakeLists.txt" ]] ||
        fail "Raiz CMake invalida: $PROJECT_ROOT"
    [[ -f "$RANGES_FILE" ]] ||
        fail "Fontes geradas ausentes: $RANGES_FILE. Execute primeiro o gerador S1-255 no PowerShell."
    [[ -f "$GAME_TOML" && -f "$AUDIT_SCRIPT" ]] ||
        fail "Arquivos de auditoria ausentes para o checkpoint S1-255."

    require_range 'F 8014C708'; require_range 'R 8014C708 28'
    require_range 'F 8017D860'; require_range 'R 8017D860 1A8'
    require_range 'F 8017DA08'; require_range 'R 8017DA08 94'
    require_range 'F 80191000'; require_range 'R 80191000 A4'
    require_range 'F 8017DA9C'; require_range 'R 8017DA9C 124'
    require_range 'F 80190EB8'; require_range 'R 80190EB8 F4'
    require_range 'F 80190FAC'; require_range 'R 80190FAC 54'
    require_range 'F 8018F10C'; require_range 'R 8018F10C 1D60'

    ! grep -Eq '^F (80103384|8016FC28|8017566C|801910A4|801914C0|80191C84|80192D6C|8019E6D0)$' "$RANGES_FILE" ||
        fail "Uma funcao fora da closure aprovada apareceu nos fontes S1-255."

    local function_count ranges_hash
    function_count="$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")"
    [[ "$function_count" == "$EXPECTED_FUNCTIONS" ]] ||
        fail "Esperadas $EXPECTED_FUNCTIONS funcoes no checkpoint S1-255; obtidas $function_count."
    ranges_hash="$(sha256sum "$RANGES_FILE" | awk '{print tolower($1)}')"
    [[ "$ranges_hash" == "$EXPECTED_RANGES_SHA256" ]] ||
        fail "Hash dos ranges S1-255 inesperado: $ranges_hash"

    require_sha256 "$FRAMEWORK_ROOT/runtime/src/main.cpp" "$EXPECTED_MAIN_SHA256"
    require_sha256 "$FRAMEWORK_ROOT/runtime/src/cdrom.c" "$EXPECTED_CDROM_C_SHA256"
    require_sha256 "$FRAMEWORK_ROOT/runtime/include/cdrom.h" "$EXPECTED_CDROM_H_SHA256"
    require_sha256 "$FRAMEWORK_ROOT/runtime/src/debug_server.c" "$EXPECTED_DEBUG_SERVER_SHA256"

    printf '\n==> Auditando fontes gerados S1-255\n'
    python "$AUDIT_SCRIPT" --config "$GAME_TOML"
}

configure_and_build() {
    printf '\n==> Configurando checkpoint limpo S1-255 (Release, PSX_DEBUG_TOOLS=OFF)\n'
    cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DPSX_DEBUG_TOOLS=OFF \
        -DPSX_STATIC_RUNTIME=ON
    printf '\n==> Compilando checkpoint limpo S1-255\n'
    cmake --build "$BUILD_DIR" --parallel "$(nproc)"
}

audit_runtime() {
    [[ -f "$EXE" ]] || fail "Executavel nao foi produzido: $EXE"
    local cache imports exe_hash
    cache="$BUILD_DIR/CMakeCache.txt"
    [[ -f "$cache" ]] || fail "CMakeCache ausente: $cache"
    grep -qxF 'CMAKE_BUILD_TYPE:STRING=Release' "$cache" ||
        fail "Checkpoint nao esta configurado como Release."
    grep -qxF 'PSX_DEBUG_TOOLS:BOOL=OFF' "$cache" ||
        fail "Checkpoint ainda possui PSX_DEBUG_TOOLS ativo."
    grep -qxF 'PSX_STATIC_RUNTIME:BOOL=ON' "$cache" ||
        fail "Checkpoint nao possui runtime estatico."

    require_symbol func_8014C708
    require_symbol func_8017D860
    require_symbol func_8017DA08
    require_symbol func_80191000
    require_symbol func_8017DA9C
    require_symbol func_80190EB8
    require_symbol func_80190FAC
    require_symbol func_8018F10C
    ! nm -C "$EXE" |
        grep -Eq '[[:space:]]T[[:space:]]+func_(80103384|8016FC28|8017566C|801910A4|801914C0|80191C84|80192D6C|8019E6D0)$' ||
        fail "O executavel contem funcao fora da closure aprovada S1-255."

    imports="$(objdump -p "$EXE" | awk '/DLL Name:/ { print $3 }')"
    if printf '%s\n' "$imports" |
        grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$'; then
        fail "O checkpoint importa DLL de runtime que deveria estar estatica."
    fi
    exe_hash="$(sha256sum "$EXE" | awk '{print toupper($1)}')"

    printf '\nCHECKPOINT RELEASE S1-255 PRONTO PARA SMOKE\n'
    printf '  Build:          %s\n' "$BUILD_DIR"
    printf '  Executavel:     %s\n' "$EXE"
    printf '  SHA-256 EXE:    %s\n' "$exe_hash"
    printf '  Configuracao:   Release, PSX_DEBUG_TOOLS=OFF, runtime estatico\n'
    printf '  Funcoes:        %s\n' "$EXPECTED_FUNCTIONS"
    printf '  Ranges SHA-256: %s\n' "${EXPECTED_RANGES_SHA256^^}"
    printf '\nAbra o executavel manualmente para o smoke final.\n'
}

main() {
    case "${1:-}" in
        '') ;;
        -h|--help) usage; return ;;
        *) usage; fail "Argumento desconhecido: $1" ;;
    esac
    [[ "${MSYSTEM:-}" == UCRT64 ]] ||
        fail "Abra o MSYS2 UCRT64 para executar este script."
    for required_command in cmake ninja nm objdump nproc sha256sum python; do
        command -v "$required_command" >/dev/null 2>&1 ||
            fail "Comando ausente no UCRT64: $required_command"
    done
    validate_sources
    configure_and_build
    audit_runtime
}

main "$@"
