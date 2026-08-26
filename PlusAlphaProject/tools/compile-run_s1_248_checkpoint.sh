#!/usr/bin/env bash
# Checkpoint limpo cumulativo S1-248: Release sem telemetria.
# Este script somente configura, compila e audita o artefato. Nunca abre o jogo.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-248"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly AUDIT_SCRIPT="$FRAMEWORK_ROOT/tools/codegen_audit_game.py"
readonly EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly EXPECTED_RANGES_SHA256="d9a50d9e9daf597ba6df3beb54fc895e1e8e9a6380c0f1095e74e571bf531e68"
readonly EXPECTED_FUNCTIONS=1035

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Uso, sempre no MSYS2 UCRT64:

  bash tools/compile-run_s1_248_checkpoint.sh

Gera o checkpoint limpo cumulativo S1-248 em Release, com
PSX_DEBUG_TOOLS=OFF e runtime estatico. O script nao gera fontes, nao
regenera a BIOS e nao abre ou fecha o jogo.
EOF
}

require_range() { grep -qxF "$1" "$RANGES_FILE" || fail "Range/funcao ausente: $1"; }
require_symbol() { nm -C "$EXE" | grep -Eq "[[:space:]]T[[:space:]]+$1$" || fail "Simbolo emitido ausente no executavel: $1"; }

validate_sources() {
    [[ -f "$PROJECT_ROOT/CMakeLists.txt" ]] || fail "Raiz CMake invalida: $PROJECT_ROOT"
    [[ -f "$RANGES_FILE" ]] || fail "Fontes geradas ausentes: $RANGES_FILE. Execute primeiro o gerador S1-248 no PowerShell."
    [[ -f "$GAME_TOML" && -f "$AUDIT_SCRIPT" ]] || fail "Arquivos de auditoria ausentes para o checkpoint S1-248."

    require_range "F 801A9DC0"; require_range "R 801A9DC0 214"
    require_range "F 801A92B8"; require_range "R 801A92B8 E4"
    require_range "F 801A7ACC"; require_range "F 801A7C34"; require_range "F 8019F3E4"; require_range "F 8019F1F0"
    require_range "F 801A9FD4"; require_range "F 801A76D4"; require_range "F 801A76EC"; require_range "F 801A7704"
    ! grep -qxF 'F 8019E6D0' "$RANGES_FILE" || fail "A funcao em quarentena 0x8019E6D0 apareceu nos fontes."

    local function_count ranges_hash
    function_count="$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")"
    [[ "$function_count" == "$EXPECTED_FUNCTIONS" ]] || fail "Esperadas $EXPECTED_FUNCTIONS funcoes emitidas no checkpoint S1-248; obtidas $function_count."
    ranges_hash="$(sha256sum "$RANGES_FILE" | awk '{print tolower($1)}')"
    [[ "$ranges_hash" == "$EXPECTED_RANGES_SHA256" ]] || fail "Hash dos ranges S1-248 inesperado: $ranges_hash"

    printf '\n==> Auditando fontes gerados S1-248\n'
    python "$AUDIT_SCRIPT" --config "$GAME_TOML"
}

configure_and_build() {
    printf '\n==> Configurando checkpoint limpo S1-248 (Release, PSX_DEBUG_TOOLS=OFF)\n'
    cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DPSX_DEBUG_TOOLS=OFF \
        -DPSX_STATIC_RUNTIME=ON
    printf '\n==> Compilando checkpoint limpo S1-248\n'
    cmake --build "$BUILD_DIR" --parallel "$(nproc)"
}

audit_runtime() {
    [[ -f "$EXE" ]] || fail "Executavel nao foi produzido: $EXE"
    local cache imports
    cache="$BUILD_DIR/CMakeCache.txt"
    [[ -f "$cache" ]] || fail "CMakeCache ausente: $cache"
    grep -qxF 'CMAKE_BUILD_TYPE:STRING=Release' "$cache" || fail "Checkpoint nao esta configurado como Release."
    grep -qxF 'PSX_DEBUG_TOOLS:BOOL=OFF' "$cache" || fail "Checkpoint ainda possui PSX_DEBUG_TOOLS ativo."
    grep -qxF 'PSX_STATIC_RUNTIME:BOOL=ON' "$cache" || fail "Checkpoint nao possui runtime estatico."

    require_symbol func_801A9DC0; require_symbol func_801A92B8
    require_symbol func_801A7ACC; require_symbol func_801A7C34; require_symbol func_8019F3E4; require_symbol func_8019F1F0
    require_symbol func_801A9FD4; require_symbol func_801A76D4; require_symbol func_801A76EC; require_symbol func_801A7704
    ! nm -C "$EXE" | grep -Eq '[[:space:]]T[[:space:]]+func_8019E6D0$' || fail "O executavel contem o candidato em quarentena func_8019E6D0."

    imports="$(objdump -p "$EXE" | awk '/DLL Name:/ { print $3 }')"
    if printf '%s\n' "$imports" | grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$'; then
        fail "O checkpoint importa DLL de runtime que deveria estar estatica."
    fi

    printf '\nCHECKPOINT S1-248 PRONTO\n'
    printf '  Build:        %s\n' "$BUILD_DIR"
    printf '  Executavel:   %s\n' "$EXE"
    printf '  Configuracao: Release, PSX_DEBUG_TOOLS=OFF, runtime estatico\n'
    printf '  Funcoes:      %s\n' "$EXPECTED_FUNCTIONS"
    printf '\nAbra o executavel manualmente para a validacao de regressao.\n'
}

main() {
    case "${1:-}" in
        "") ;;
        -h|--help) usage; return ;;
        *) usage; fail "Argumento desconhecido: $1" ;;
    esac
    [[ "${MSYSTEM:-}" == "UCRT64" ]] || fail "Abra o MSYS2 UCRT64 para executar este script."
    for required_command in cmake ninja nm objdump nproc sha256sum python; do
        command -v "$required_command" >/dev/null 2>&1 || fail "Comando ausente no UCRT64: $required_command"
    done
    validate_sources
    configure_and_build
    audit_runtime
}

main "$@"
